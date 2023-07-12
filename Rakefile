require 'pg_builder'
spec = Gem::Specification.find_by_name 'pg_builder'
load "#{spec.gem_dir}/lib/pg_builder/Rakefile"

task :build_extension => :complete do
    sh "cat extension_header.sql build/schema.sql > fsm--0.1.sql"
end