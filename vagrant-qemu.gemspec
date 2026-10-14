$:.unshift File.expand_path("../lib", __FILE__)
require "vagrant-qemu/version"

Gem::Specification.new do |s|
  s.name          = "vagrant-qemu"
  s.version       = VagrantPlugins::QEMU::VERSION
  s.platform      = Gem::Platform::RUBY
  s.license       = "MIT"
  s.authors       = "ppggff"
  s.email         = "pgf00a@gmail.com"
  s.homepage      = "https://github.com/ppggff/vagrant-qemu"
  s.summary       = "Enables Vagrant to manage machines with QEMU."
  s.description   = "Enables Vagrant to manage machines with QEMU."

  s.required_rubygems_version = ">= 1.3.6"
  s.rubyforge_project         = "vagrant-qemu"

  # Ship only what the plugin needs at run time: specs, CI files, examples
  # and release scripts stay in the repository.
  s.files = Dir.chdir(File.dirname(__FILE__)) do
    Dir.glob("{lib,locales}/**/*").select { |f| File.file?(f) } +
      %w[LICENSE README.md CHANGELOG.md]
  end
  s.require_path  = 'lib'
end
