require 'pg_builder'
require './version'
spec = Gem::Specification.find_by_name 'pg_builder'
load "#{spec.gem_dir}/lib/pg_builder/Rakefile"

task :build_extension => :complete do
    sh "cat extension_header.sql build/schema.sql > fsm--#{PG_FSM_VERSION}.sql"
end