#include <ruby.h>
#include <ruby/encoding.h>
#include <string.h>
#include <iostream>
#include "base/logging.h"
#include "net/spdy/spdy_framer.h"

#define PROTECTFUNC(f) ((VALUE (*)(VALUE)) f)
#define VALUEFUNC(f) ((VALUE (*)(ANYARGS)) f)
#define VOIDFUNC(f)  ((RUBY_DATA_FUNC) f)
#define INTFUNC(f) ((int (*)(ANYARGS)) f)
#define FRAME_SIZE(frame) (frame->length() + SpdyFrame::size())

static VALUE mSpdy;
static VALUE cSpdyFramer;
static VALUE cSpdyFrame;
static ID id_new_stream;
static ID id_remove_stream;
static ID id_upload_data;
static ID id_syn_reply;

namespace logging {
	const char* const log_severity_names[LOG_NUM_SEVERITIES] = {
		"INFO", "WARNING", "ERROR", "ERROR_REPORT", "FATAL" };
	
	LogMessage::LogMessage(char const* file, int line, int level) {
        stream_ << log_severity_names[level] << " " << file << "(" << line << ") ";
	}
	
	LogMessage::LogMessage(const char* file, int line, const CheckOpString& result) {
        stream_ << "FATAL " << file << "(" << line << ") " << (*result.str_);
	}
	
	LogMessage::~LogMessage() {
		stream_ << std::endl;
		std::string str_newline(stream_.str());
		std::cerr << str_newline;
	}
}

using namespace spdy;

class FramerCallbacks : public SpdyFramerVisitorInterface {
public:
	FramerCallbacks(SpdyFramer *framer, VALUE ruby_obj) :
	framer_(framer), obj_(ruby_obj) {
//		rb_gc_register_address(&obj_);
	}

	~FramerCallbacks() {
//		rb_gc_unregister_address(&obj_);
	}

	virtual void OnError(SpdyFramer* framer) {
		LOG(ERROR) <<  "SpdyFramer error: " << framer->ErrorCodeToString(framer->error_code());
		/*
		if (rb_respond_to(obj_, id_framer_error)) {
			VALUE argv[] = {(VALUE)framer};
			VALUE rb_framer = rb_class_new_instance(1, argv, cSpdyFramer);
			rb_funcall(obj_, on_error, 1, rb_framer);
		}*/
	}

	virtual void OnControl(const SpdyControlFrame* frame) {
		SpdyHeaderBlock headers;
		bool parsed_headers = false;
		switch (frame->type()) {
			case SYN_STREAM:
			{
				const SpdySynStreamControlFrame* syn_stream =
					reinterpret_cast<const SpdySynStreamControlFrame*>(frame);
				parsed_headers = framer_->ParseHeaderBlock(frame, &headers);
//				LOG(INFO) << "OnSyn(" << syn_stream->stream_id() << ")";
//				LOG(INFO) << "headers parsed?: " << (parsed_headers? "yes": "no");
				VALUE hdrs = rb_hash_new();
				VALUE key, val;
				for (SpdyHeaderBlock::iterator i = headers.begin(); i != headers.end();	++i) {
//					LOG(INFO) << i->first << ": " << i->second;
					key = rb_str_new2(i->first.c_str());
					val = rb_str_new2(i->second.c_str());
					rb_hash_aset(hdrs, key, val);
				}

				SpdyHeaderBlock::iterator method = headers.find("method");
				SpdyHeaderBlock::iterator url = headers.find("url");
				if (url == headers.end() || method == headers.end()) {
					LOG(WARNING) << "didn't find method or url.";
					//break;
				}
				VALUE stream_id = INT2NUM(syn_stream->stream_id());
				rb_funcall(obj_, id_new_stream, 2, stream_id, hdrs);
			}
			break;
			case SYN_REPLY:
			{
				parsed_headers = framer_->ParseHeaderBlock(frame, &headers);
				const SpdySynReplyControlFrame *syn_reply = reinterpret_cast<const SpdySynReplyControlFrame*>(frame);
				//LOG(INFO) << "OnSynReply(" << syn_reply->stream_id() << ")";
				VALUE stream_id = INT2NUM(syn_reply->stream_id());
				VALUE hdrs = Qnil;
				if (parsed_headers) {
					hdrs = rb_hash_new();
					VALUE key, val;
					for (SpdyHeaderBlock::iterator i = headers.begin(); i != headers.end();	++i) {
						key = rb_str_new2(i->first.c_str());
						val = rb_str_new2(i->second.c_str());
						rb_hash_aset(hdrs, key, val);
					}
				}
				rb_funcall(obj_, id_syn_reply, 2, stream_id, hdrs);
			}
			break;
			case RST_STREAM:
			{
				const SpdyRstStreamControlFrame* rst_stream = 
					reinterpret_cast<const SpdyRstStreamControlFrame*>(frame);
				LOG(INFO) << "OnRst(" << rst_stream->stream_id() << ")";
				VALUE stream_id = INT2NUM(rst_stream->stream_id());
				rb_funcall(obj_, id_remove_stream, 1, stream_id);
			}
			break;

			default:
			LOG(FATAL) << "Unknown control frame type";
		}
	}

	virtual void OnStreamFrameData(spdy::SpdyStreamId stream_id, const char* data, size_t len) {
//		LOG(INFO) << "OnStreamFrameData " << len;
		VALUE str;
		if (len > 0) {
			str = rb_enc_str_new(data, len, rb_ascii8bit_encoding());
		} else {
			str = Qnil;
		}
		rb_funcall(obj_, id_upload_data, 2, INT2NUM(stream_id), str);
	}

/*
	void mark() {
		rb_gc_mark(obj_);
	}
*/

private:
	SpdyFramer *framer_;
	VALUE obj_;
};

static void SpdyFramer_destroy(spdy::SpdyFramer *framer) {
	framer->set_visitor(NULL);
	delete framer;
}

static VALUE _spdy_framer_alloc(VALUE klass) {
	VALUE obj;
	SpdyFramer *framer = new spdy::SpdyFramer();
	obj = Data_Wrap_Struct(klass, NULL, SpdyFramer_destroy, framer);
	return obj;
}

/*
 *  Document-method: initialize
 *  call-seq:
 *    Framer.new(callback) -> new_framer
 *
 *  The callback must implement the following methods:
 *  <code>new_stream</code>, <code>remove_stream</code>
 */
static VALUE _wrap_framer_init(VALUE self, VALUE cb) {
	spdy::SpdyFramer *framer;
	Data_Get_Struct(self, spdy::SpdyFramer, framer);
	framer->set_visitor(new FramerCallbacks(framer, cb));
	rb_iv_set(self, "@cb", cb);
	return self;
}

/*
 *  call-seq:
 *    framer.process_input(buf) -> Fixnum
 *
 *  Returns the number of bytes consumed and calls the callbacks
 *  when applicable.
 */
static VALUE _wrap_framer_process_input(VALUE self, VALUE buf) {
	spdy::SpdyFramer *framer;
	VALUE str = StringValue(buf);
	Data_Get_Struct(self, spdy::SpdyFramer, framer);
	size_t len = framer->ProcessInput(RSTRING_PTR(str), RSTRING_LEN(str));
	return INT2NUM(len);
}

static int _iterate_headers(VALUE key, VALUE val, VALUE hdrs) {
	spdy::SpdyHeaderBlock *headers = reinterpret_cast<spdy::SpdyHeaderBlock*>(hdrs);
	VALUE k = StringValue(key);
	VALUE v = StringValue(val);
	std::string name(RSTRING_PTR(k), RSTRING_LEN(k));
	std::string value(RSTRING_PTR(v), RSTRING_LEN(v));
	(*headers)[name] = value;
	return ST_CONTINUE;
}

/*
 *  call-seq:
 *    framer.create_syn_reply(stream_id, flags, compressed, headers_hash) -> Spdy::Frame
 *
 *  Creates a Control SPDY frame.
 */
static VALUE _wrap_framer_create_syn_reply(VALUE self, VALUE stream_id,
		VALUE flags, VALUE compressed, VALUE headers) {
	SpdyStreamId sid = NUM2INT(stream_id);
	SpdyControlFlags fl = static_cast<SpdyControlFlags>(NUM2CHR(flags));
	bool comp = (compressed == Qtrue);
	SpdyHeaderBlock *hdrs = new SpdyHeaderBlock;
	rb_hash_foreach(headers, INTFUNC(_iterate_headers), reinterpret_cast<VALUE>(hdrs));

	SpdyFramer *framer;
	Data_Get_Struct(self, SpdyFramer, framer);
	SpdySynReplyControlFrame* fr = framer->CreateSynReply(sid, fl, comp, hdrs);
	delete(hdrs);
//	LOG(INFO) << "createSyn: " << FRAME_SIZE(fr);
	VALUE control_frame = rb_class_new_instance(0, NULL, cSpdyFrame);
	DATA_PTR(control_frame) = fr;

	return control_frame;
}

/*
 *  call-seq:
 *    framer.create_syn_stream(stream_id, assoc_stream_id, priority, flags, compressed, headers_hash) -> Spdy::Frame
 *
 *  Creates a Control SPDY frame.
 */
static VALUE _wrap_framer_create_syn_stream(VALUE self, VALUE stream_id, VALUE assoc_stream_id,
	VALUE priority, VALUE flags, VALUE compressed, VALUE headers) {
	SpdyStreamId sid = NUM2INT(stream_id);
	SpdyStreamId asid = NUM2INT(assoc_stream_id);
	int prio = NUM2INT(priority);
	SpdyControlFlags fl = static_cast<SpdyControlFlags>(NUM2CHR(flags));
	bool comp = (compressed == Qtrue);
	SpdyHeaderBlock *hdrs = new SpdyHeaderBlock;
	rb_hash_foreach(headers, INTFUNC(_iterate_headers), reinterpret_cast<VALUE>(hdrs));

	SpdyFramer *framer;
	Data_Get_Struct(self, SpdyFramer, framer);

	SpdySynStreamControlFrame* fr = framer->CreateSynStream(sid, asid, prio, fl, comp, hdrs);
	delete(hdrs);
	VALUE control_frame = rb_class_new_instance(0, NULL, cSpdyFrame);
	DATA_PTR(control_frame) = fr;

	return control_frame;
}

/*
 *  call-seq:
 *    framer.create_data_frame(stream_id, data, flags) -> Spdy::Frame
 *
 *  Creates a Data SPDY frame.
 */
static VALUE _wrap_framer_create_data(VALUE self, VALUE stream_id, VALUE data, VALUE flags) {
	SpdyStreamId sid = NUM2INT(stream_id);
	SpdyDataFlags fl = static_cast<SpdyDataFlags>(NUM2CHR(flags));
	SpdyFramer *framer;
	Data_Get_Struct(self, SpdyFramer, framer);
	SpdyDataFrame *fr;
	if (data == Qnil) {
		fr = framer->CreateDataFrame(sid, NULL, 0, fl);
	} else {
		VALUE str = StringValue(data);
//		rb_enc_associate(str, rb_ascii8bit_encoding());
		fr = framer->CreateDataFrame(sid, RSTRING_PTR(str), (int)RSTRING_LEN(str), fl);
	}

	VALUE data_frame = rb_class_new_instance(0, NULL, cSpdyFrame);
	DATA_PTR(data_frame) = fr;

	return data_frame;
}
/*
static VALUE _wrap_new_spdy_framer(VALUE self, VALUE arg) {
	net::SpdyFramer *framer = new SpdyFramer();
	DATA_PTR(self) = framer;
	return self;
}
*/

/* Frame class */
static void SpdyFrame_destroy(spdy::SpdyFrame *frame) {
	delete(frame);
}

static VALUE _spdy_frame_alloc(VALUE klass) {
	VALUE obj = Data_Wrap_Struct(klass, NULL, SpdyFrame_destroy, NULL);
	return obj;
}

/*
 *  call-seq:
 *    frame.data -> String
 *
 *  Returns the frame binary data as String.
 */
static VALUE _wrap_frame_data(VALUE self) {
	SpdyFrame *frame;
	Data_Get_Struct(self, SpdyFrame, frame);
	VALUE data = rb_enc_str_new(frame->data(), FRAME_SIZE(frame), rb_ascii8bit_encoding());
	return data;
}

/*
 *  call-seq:
 *    frame.size -> Fixnum
 *
 *  Returns the size of the frame data.
 */
static VALUE _wrap_frame_size(VALUE self) {
	SpdyFrame *frame;
	Data_Get_Struct(self, SpdyFrame, frame);
	return INT2NUM(FRAME_SIZE(frame));
}

extern "C" void Init_set_sock_opt(void);

#ifdef __cplusplus
extern "C"
#endif

void Init_Spdy(void) {
	mSpdy = rb_define_module("Spdy");

	cSpdyFramer = rb_define_class_under(mSpdy, "Framer", rb_cObject);
	rb_define_alloc_func(cSpdyFramer, _spdy_framer_alloc);
	rb_define_method(cSpdyFramer, "process_input", VALUEFUNC(_wrap_framer_process_input), 1);
	rb_define_method(cSpdyFramer, "create_syn_reply", VALUEFUNC(_wrap_framer_create_syn_reply), 4);
	rb_define_method(cSpdyFramer, "create_syn_stream", VALUEFUNC(_wrap_framer_create_syn_stream), 6);
	rb_define_method(cSpdyFramer, "create_data_frame", VALUEFUNC(_wrap_framer_create_data), 3);
	rb_define_method(cSpdyFramer, "initialize", VALUEFUNC(_wrap_framer_init), 1);
	rb_define_attr(cSpdyFramer, "cb", 1, 0); // attr_reader :cb
	
	cSpdyFrame = rb_define_class_under(mSpdy, "Frame", rb_cObject);
	rb_define_alloc_func(cSpdyFrame, _spdy_frame_alloc);
//	rb_define_method(cSpdyFrame, "initialize", VALUEFUNC(_wrap_frame_init), 0);
	rb_define_method(cSpdyFrame, "data", VALUEFUNC(_wrap_frame_data), 0);
	rb_define_method(cSpdyFrame, "size", VALUEFUNC(_wrap_frame_size), 0);
	
	id_new_stream = rb_intern("new_stream");
	id_remove_stream = rb_intern("remove_stream");
	id_upload_data = rb_intern("upload_data");
	id_syn_reply = rb_intern("syn_reply");

	Init_set_sock_opt();
}
