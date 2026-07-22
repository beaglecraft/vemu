# frozen_string_literal: true

Gem::Specification.new do |s|
  s.name = 'vemu'
  s.version = '0.1.0-alpha1'
  s.platform = Gem::Platform::RUBY
  s.summary = 'Virtual Machines'

  s.homepage = 'https://github.com/beaglecraft/vemu'
  s.authors  = ['André Diego Piske']
  s.email    = 'andrepiske@gmail.com'
  s.license  = 'MIT'

  s.files = Dir['lib/**/*', 'LICENSE'].reject { |f| File.directory?(f) }

  s.executables = []
  s.require_paths = ['lib']

  s.add_dependency 'json', '~> 2.10'
  s.add_dependency 'net-ssh', '~> 7.3'
  s.add_dependency 'ed25519', '~> 1.4'
  s.add_dependency 'bcrypt_pbkdf', '~> 1.1'
  s.add_dependency 'psych', '~> 5.2'
  s.add_dependency 'logger', '~> 1.7'

  s.required_ruby_version = '>= 3.4.0'

  s.metadata = {
    'bug_tracker_uri' => 'https://github.com/beaglecraft/vemu/issues',
    'changelog_uri' => 'https://github.com/beaglecraft/vemu/blob/main/CHANGELOG.md',
    'documentation_uri' => 'https://github.com/beaglecraft/vemu/blob/main/README.md',
    'homepage_uri' => 'https://github.com/beaglecraft/vemu',
    'source_code_uri' => 'https://github.com/beaglecraft/vemu',
    'wiki_uri' => 'https://github.com/beaglecraft/vemu/wiki'
  }
end
