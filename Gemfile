# frozen_string_literal: true

source "https://rubygems.org"

gemspec

core = ENV.fetch("LEPUS_SAGA_PATH", File.expand_path("../lepus-saga", __dir__))
if File.directory?(core)
  gem "lepus-saga", path: core
else
  gem "lepus-saga", github: "marcosgz/lepus-saga"
end

gem "sqlite3", ">= 2.1"
