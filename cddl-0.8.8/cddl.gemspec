spec = Gem::Specification.new do |s|
  s.name = 'cddl'
  s.version = '0.8.8'
  s.summary = "CDDL generator and validator."
  s.description = %{A parser, generator, and validator for CDDL}
  s.add_dependency('cbor-diag')
  s.add_dependency('abnc')
  s.add_dependency('json')
  s.add_dependency('regexp-examples') # , '1.1.0')
  s.add_dependency('colorize')
  s.files = `git ls-files`.split("\n").grep(/^[a-z]/)
  s.files = Dir['lib/**/*.rb'] + %w(cddl.gemspec) + Dir['data/**/*.abnf'] + Dir['data/**/*.cddl'] + Dir['test-data/**/*.cddl'] + Dir['test/**/*.rb']
  s.require_path = 'lib'
  s.executables = ['cddl']
  s.default_executable = 'cddl'
  s.required_ruby_version = '>= 2.0'
  s.author = "Carsten Bormann"
  s.email = "cabo@tzi.org"
  s.homepage = "http://github.com/cabo/cddl"
  s.license = 'MIT'
end
