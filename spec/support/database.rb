# frozen_string_literal: true

module Database
  SQLITE_PATH = File.expand_path("../../tmp/lepus_saga_test.sqlite3", __dir__)

  module_function

  def db = @db

  # SQLite runs from a file rather than :memory: so the threaded examples share
  # one database across connections, and waits for a lock with
  # busy_handler_timeout, which lets other threads run while it waits.
  def connect!
    @db = if ENV["DATABASE_URL"]
      Sequel.connect(ENV["DATABASE_URL"], max_connections: 10, fractional_seconds: true)
    else
      FileUtils.mkdir_p(File.dirname(SQLITE_PATH))
      FileUtils.rm_f(Dir["#{SQLITE_PATH}*"])
      Sequel.sqlite(SQLITE_PATH, max_connections: 10, after_connect: ->(connection) { connection.busy_handler_timeout = 10_000 })
    end
    @db.loggers << Logger.new($stdout) if ENV["DEBUG"]
    @db
  end

  def sqlite? = db.database_type == :sqlite

  def load_schema!
    db.drop_table?(:saga_step_attempts, :saga_executions, Lepus::Saga::Sequel::MIGRATIONS_TABLE)
    Lepus::Saga::Sequel.migrate(db)
  end

  def clean!
    db[:saga_step_attempts].delete
    db[:saga_executions].delete
  end

  # Collects the SQL the database runs inside the block.
  def capture_sql
    io = StringIO.new
    logger = Logger.new(io)
    db.loggers << logger
    yield
    io.string.lines
  ensure
    db.loggers.delete(logger)
  end
end
