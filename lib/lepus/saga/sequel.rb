# frozen_string_literal: true

require "json"
require "securerandom"
require "lepus/saga"
require "sequel"
require_relative "sequel/version"

module Lepus
  module Saga
    # Sequel models for the saga tables. Select the store with
    #
    #   Lepus::Saga.configure { |config| config.store = :sequel }
    #
    # The models bind to `Lepus::Saga::Sequel.db` (Sequel::Model.db unless
    # set) the first time they are used, so set it and run the migrations
    # before that.
    module Sequel
      MIGRATIONS_PATH = File.expand_path("sequel/migrations", __dir__)
      MIGRATIONS_TABLE = :lepus_saga_schema_info

      autoload :Record, "lepus/saga/sequel/record"
      autoload :Execution, "lepus/saga/sequel/execution"
      autoload :StepAttempt, "lepus/saga/sequel/step_attempt"

      class << self
        attr_writer :db

        def db
          @db || ::Sequel::Model.db
        end

        # Creates (or rolls back, with `target:`) the saga tables, tracking the
        # version in its own table so it never collides with the app's
        # migrations.
        def migrate(db = self.db, **options)
          ::Sequel.extension :migration
          ::Sequel::Migrator.run(db, MIGRATIONS_PATH, table: MIGRATIONS_TABLE, **options)
        end
      end
    end
  end
end

require_relative "stores/sequel"
