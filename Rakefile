require 'rdoc/task'

desc 'Default: build gem'
task :default => :build

begin
  require 'jeweler'
  Jeweler::Tasks.new do |gemspec|
    gemspec.name = "spdy"
    gemspec.version = '0.1'
    gemspec.summary = "SPDY daemon"
    gemspec.description = gemspec.summary
    gemspec.email = "romanbsd@yahoo.com"
    gemspec.homepage = "http://github.com/romanbsd/spdy"
    gemspec.authors = ["Roman Shterenzon"]
    gemspec.add_dependency("eventmachine", "~> 0.12.10")
    gemspec.add_dependency("daemons", "~> 1.1.3")
    gemspec.add_dependency("em-http-request", "~> 0.3.0")
    gemspec.executables = 'spdyd'
    gemspec.files = `git ls-files`.split("\n")
    gemspec.test_files = `git ls-files -- {test,spec,features}/*`.split("\n")
    gemspec.executables = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  end
rescue LoadError
  puts "Jeweler not available. Install it with: gem install jeweler"
end

Rake::RDocTask.new do |rd|
  rd.rdoc_files.include("lib/**/*.rb", "ext/module.cc")
  rd.rdoc_dir = 'doc'
end

begin
  require 'yard'
  YARD::Rake::YardocTask.new do |yard|
    yard.options = ['--title',  'SPDY']
    yard.files = Dir["ext/*.cc", "lib/**/*.rb"]
  end
rescue LoadError
end
