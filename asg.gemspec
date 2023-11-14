
lib = File.expand_path("../lib", __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "asg/version"

Gem::Specification.new do |spec|
  spec.name          = "asg"
  spec.version       = Asg::VERSION
  spec.authors       = ["fzdp"]
  spec.email         = ["fzdp01@gmail.com"]

  spec.summary       = "A simple git created by Ruby"
  spec.description   = "Create git from scratch"
  spec.homepage      = "https://github.com/fzdp/asg"
  spec.license       = "MIT"

  # Prevent pushing this gem to RubyGems.org. To allow pushes either set the 'allowed_push_host'
  # to allow pushing to a single host or delete this section to allow pushing to any host.
  if spec.respond_to?(:metadata)
    spec.metadata["homepage_uri"] = spec.homepage
    # spec.metadata["source_code_uri"] = ""
    # spec.metadata["changelog_uri"] = ""
  else
    raise "RubyGems 2.0 or newer is required to protect against " \
      "public gem pushes."
  end

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files         = Dir["lib/**/*"]
  spec.bindir        = "exe"
  spec.executables   = ["asg"]

  spec.add_development_dependency "bundler", "~> 1.17"
  spec.add_development_dependency "rake", "~> 10.0"
  spec.add_development_dependency "rspec", "~> 3.0"
end
