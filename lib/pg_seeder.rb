require "pathname"

class PgSeeder

  class CommandFailed < StandardError; end

  attr_reader :current_env, :version, :root

  def initialize(current_env: Rails.env, version: Time.now.to_i.to_s, root: Rails.root)
    @current_env = current_env
    @version = version
    @root = root
    @setups = []
    @generates = []
  end

  def stored_version
    File.read(directory.join("SEED_VERSION")).strip
  rescue
    nil
  end

  def restorable?
    version_match? &&
    dump_restorable? &&
    attachment_data_restorable?
  end

  def version_match?
    version == stored_version
  end

  def dump_restorable?
    directory.join("seed.pg_dump").exist?
  end

  def attachment_data_restorable?
    directory.join("seed.tar.bz2").exist?
  end

  def setup(env: current_env, &block)
    @setups << block if [*env].include?(current_env)
  end

  def generate(env: current_env, &block)
    @generates << block if [*env].include?(current_env)
  end

  def execute(with_dump: true, ignore_restore: false)
    return restore if !ignore_restore && restorable?
    puts "\033[33;5;7m Generating seed data \033[0m"
    (@setups + @generates).each(&:call)
    store if with_dump
  end

  def restore
    puts "\033[33;5;7m Restoring \033[0m from db/seed.psql and attachment data from db/seed.tar.bz2"
    restore_dump
    restore_attachment_data
  end

  def restore_dump
    cmd "pg_restore " + %W[
      --username='#{db_config[:username]}'
      --host='#{db_config[:hostname]}'
      --clean
      --if-exists
      --jobs 4
      --no-acl
      --dbname='#{db_config[:database]}'
    '#{directory.join("seed.pg_dump")}'
    ].join(" ")
  end

  def restore_attachment_data
    cmd "tar xjf '#{directory.join("seed.tar.bz2")}'"
  end

  def store
    puts "\033[33;5;7m Storing \033[0m database to db/seed/seed.pg_dump and attachment data to db/seed/seed.tar.bz2"
    store_dump
    store_attachment_data
    puts "\033[33;5;7m Writing new seed version \033[0m #{version}"
    File.open(directory.join("SEED_VERSION"), "w") { |f| f.write(version) }
  end

  def store_dump
    cmd "pg_dump " + %W[
      --username='#{db_config[:username]}'
      --host='#{db_config[:hostname]}'
      --clean
      --no-owner
      --no-acl
      --compress=9
      --format=c
      '#{db_config[:database]}'
      > '#{directory.join("seed.pg_dump")}'
    ].join(" ")
  end

  def store_attachment_data
    cmd "tar cjf '#{directory.join("seed.tar.bz2")}' public/system 2>&1" if root.join("public/system").exist?
  end

  def cmd(line)
    unless system(line)
      raise CommandFailed, "command failed '#{line}'"
    end
  end

  def db_config
    ActiveRecord::Base.connection_config
  end

  def directory
    directory = root.join("db/seed")
  ensure
    FileUtils.mkdir_p(directory)
  end

end

