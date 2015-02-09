require 'new_relic/recipes'
require 'bundler/capistrano'
require 'delayed/recipes'
set :stage, "test" unless exists? :stage
if stage != "development"
  require 'rvm/capistrano'
  require 'rvm/capistrano/alias_and_wrapp'
  set :rvm_ruby_string, ENV['GEM_HOME'].gsub(/.*\//,"")
  before 'deploy', 'rvm:create_alias'
  before 'deploy', 'rvm:create_wrappers'
end

# This adds a task that precompiles assets for the asset pipeline
load 'deploy/assets'

set :application, "planningalerts.org.au/app"
set :repository,  "git://github.com/openaustralia/planningalerts-app.git"

set :use_sudo, false
set :user, "deploy"
set :scm, :git
set :rails_env, "production" #added for delayed job

if stage == "production"
  server "kedumba.openaustraliafoundation.org.au", :app, :web, :db, :primary => true
  set :deploy_to, "/srv/www/www.#{application}"
elsif stage == "test"
  server "kedumba.openaustraliafoundation.org.au", :app, :web, :db, :primary => true
  set :deploy_to, "/srv/www/test.#{application}"
elsif stage == "development"
  server "planningalerts.org.au.dev", :app, :web, :db, :primary => true
  set :deploy_to, "/srv/www"
end

# We need to run this after our collector mongrels are up and running
# This goes out even if the deploy fails, sadly
after "deploy:update", "newrelic:notice_deployment"

before "deploy:restart", "foreman:restart"

namespace :deploy do
  desc "After a code update, we link additional config and the scrapers"
  before "deploy:assets:precompile" do
    links = {
            "#{release_path}/config/database.yml"               => "#{shared_path}/database.yml",
            "#{release_path}/config/throttling.yml"             => "#{shared_path}/throttling.yml",
            "#{release_path}/app/models/configuration.rb"       => "#{shared_path}/configuration.rb",
            "#{release_path}/config/production.sphinx.conf"     => "#{shared_path}/production.sphinx.conf",
            "#{release_path}/config/sphinx.yml"                 => "#{shared_path}/sphinx.yml",
            "#{release_path}/public/sitemap.xml"                => "#{shared_path}/sitemap.xml",
            "#{release_path}/public/sitemaps"                   => "#{shared_path}/sitemaps",
            "#{release_path}/public/assets"                     => "#{shared_path}/assets",
    }

    # "ln -sf <a> <b>" creates a symbolic link but deletes <b> if it already exists
    run links.map {|a| "ln -sf #{a.last} #{a.first}"}.join(";")
  end

  task :restart, :except => { :no_release => true } do
    run "touch #{File.join(current_path,'tmp','restart.txt')}"
  end

  desc "Deploys and starts a `cold' application. Uses db:schema:load instead of Capistrano's default of db:migrate"
  task :cold do
    update
    load_schema
    start
  end

  desc "Identical to Capistrano's db:migrate task but does db:schema:load instead"
  task :load_schema, roles: :app do
    rake = fetch(:rake, "rake")
    rails_env = fetch(:rails_env, "production")
    migrate_env = fetch(:migrate_env, "")
    migrate_target = fetch(:migrate_target, :latest)

    directory = case migrate_target.to_sym
      when :current then current_path
      when :latest  then latest_release
      else raise ArgumentError, "unknown migration target #{migrate_target.inspect}"
      end

    run "cd #{directory} && #{rake} RAILS_ENV=#{rails_env} #{migrate_env} db:schema:load"
  end

  after "deploy:setup" do
    run "mkdir -p #{shared_path}/sitemaps"
  end
end

namespace :foreman do
  desc "Export the Procfile to Ubuntu's upstart scripts"
  task :export, roles: :app do
    run "cd #{current_path} && sudo bundle exec foreman export upstart /etc/init -u deploy -a planningalerts -f Procfile.production -l /srv/www/www.planningalerts.org.au/log --root /srv/www/www.planningalerts.org.au/app/current"
  end

  desc "Start the application services"
  task :start, roles: :app do
    sudo "service planningalerts start"
  end

  desc "Stop the application services"
  task :stop, roles: :app do
    sudo "service planningalerts stop"
  end

  desc "Restart the application services"
  task :restart, roles: :app do
    run "sudo service planningalerts restart"
  end
end
