# frozen_string_literal: true

require 'rubygems'
require 'rake'

namespace :seek do
  # these are the tasks required for this version upgrade
  task upgrade_version_tasks: %i[
    environment
    update_samples_json
  ]

  # these are the tasks that are executes for each upgrade as standard, and rarely change
  task standard_upgrade_tasks: %i[
    environment
    clear_filestore_tmp
    repopulate_auth_lookup_tables
  ]

  desc('upgrades SEEK from the last released version to the latest released version')
  task(upgrade: [:environment]) do
    puts "Starting upgrade ..."
    puts "... trimming old session data ..."
    Rake::Task['db:sessions:trim'].invoke
    puts "... migrating database ..."
    Rake::Task['db:migrate'].invoke
    Rake::Task['tmp:clear'].invoke

    solr = Seek::Config.solr_enabled
    Seek::Config.solr_enabled = false

    begin
      puts "... performing upgrade tasks ..."
      Rake::Task['seek:standard_upgrade_tasks'].invoke
      Rake::Task['seek:upgrade_version_tasks'].invoke

      Seek::Config.solr_enabled = solr
      puts "... queuing search reindexing jobs ..."
      Rake::Task['seek:reindex_all'].invoke if solr

      puts 'Upgrade completed successfully'
    ensure
      Seek::Config.solr_enabled = solr
    end
  end

  task(update_samples_json: :environment) do
    puts '... converting stored sample JSON ...'
    SampleType.all.each do |sample_type|

      # gather the attributes that need updating
      attributes_for_update = sample_type.sample_attributes.select do |attr|
        attr.accessor_name != attr.original_accessor_name
      end

      if attributes_for_update.any?
        # work through each sample
        sample_type.samples.each do |sample|
          json = JSON.parse(sample.json_metadata)
          attributes_for_update.each do |attr|
            # replace the json key
            json[attr.accessor_name] = json.delete(attr.original_accessor_name)
          end
          sample.update_column(:json_metadata,json.to_json)
        end

        # update the original accessor name for each affected attribute
        attributes_for_update.each do |attr|
          attr.update_column(:original_accessor_name, attr.accessor_name)
        end
      end
    end
    puts " ... finished updating sample JSON"
  end
end
