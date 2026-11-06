# frozen_string_literal: true

require_relative "lib/lepus/saga/sequel/version"

Gem::Specification.new do |spec|
  spec.name = "lepus-saga-sequel"
  spec.version = Lepus::Saga::Sequel::VERSION
  spec.authors = ["Marcos G. Zimmermann"]
  spec.email = ["mgzmaster@gmail.com"]

  spec.summary = "Sequel store for Lepus::Saga"
  spec.description = "Keeps lepus-saga executions and step attempts in Sequel models (PostgreSQL, MySQL/MariaDB, SQLite), with migrations for the tables"
  spec.homepage = "https://github.com/marcosgz/lepus-saga-sequel"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.3.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/marcosgz/lepus-saga-sequel"
  spec.metadata["changelog_uri"] = "https://github.com/marcosgz/lepus-saga-sequel/blob/master/CHANGELOG.md"

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    `git ls-files -z`.split("\x0").reject do |f|
      (f == __FILE__) || f.match(%r{\A(?:(?:bin|ci|test|spec|features)/|\.(?:git|github|rspec|rubocop)|docker-compose)})
    end
  end
  spec.require_paths = ["lib"]

  spec.add_dependency "lepus-saga", "~> 0.3.0"
  spec.add_dependency "sequel", ">= 5.60"
  spec.add_development_dependency "pry"
  spec.add_development_dependency "rake"
  spec.add_development_dependency "rspec"
  spec.add_development_dependency "rubocop"
  spec.add_development_dependency "rubocop-performance"
  spec.add_development_dependency "rubocop-rspec"
  spec.add_development_dependency "standard"
end
