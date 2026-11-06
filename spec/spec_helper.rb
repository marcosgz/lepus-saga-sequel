# frozen_string_literal: true

require "bundler/setup"
require "fileutils"
require "logger"
require "stringio"
require "lepus/saga/sequel"
require "lepus/saga/rspec"
require "pry"

Dir[File.expand_path("support/**/*.rb", __dir__)].sort.each { |file| require file }

Lepus.logger = Logger.new(File::NULL)
Sequel.default_timezone = :utc
Database.connect!
Database.load_schema!
Lepus::Saga::Sequel.db = Database.db
Lepus::Saga.configure { |config| config.store = :sequel }

RSpec.configure do |config|
  config.example_status_persistence_file_path = ".rspec_status"
  config.disable_monkey_patching!

  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.filter_run_excluding row_locks: true if Database.sqlite?

  config.before do
    Lepus::Testing.enable!
    Lepus::Producers::Hooks.reset!
    Lepus::Testing.clear_all_messages!
  end

  config.after do
    Lepus::Testing.disable!
    Database.clean!
  end
end
