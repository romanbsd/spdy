#include <sys/socket.h>
#include <ruby.h>

int evma_get_file_descriptor(unsigned long signature);

/* Set socket option
 *
 * call-seq:
 *    EM.set_sock_opt(connection, level, optname, value) -> true
 */
static VALUE t_set_sock_opt (VALUE self, VALUE signature, VALUE lev, VALUE optname, VALUE optval)
{
	int fd = evma_get_file_descriptor(NUM2ULONG(signature));
	int level = NUM2INT(lev), option = NUM2INT(optname);
	int val = NUM2INT(optval);

	if (setsockopt(fd, level, option, &val, sizeof(val)) < 0) {
		rb_sys_fail("setsockopt");
	}

	return Qtrue;
}

void Init_set_sock_opt(void)
{
	VALUE EmModule;
	ID em_id = rb_intern("EventMachine");
	if (rb_const_defined(rb_cObject, em_id)) {
		EmModule = rb_const_get(rb_cObject, em_id);
	}
	else {
		EmModule = rb_define_module("EventMachine");
	}
	rb_define_module_function(EmModule, "set_sock_opt", t_set_sock_opt, 4);
}
