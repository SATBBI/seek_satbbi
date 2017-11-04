module Seek
  module Openbis

    class SeekUtil

      def createObisAssay(assay_params, creator, obis_asset)

        zample = obis_asset.content
        assay_params[:assay_class_id] ||= AssayClass.for_type("experimental").id
        assay_params[:title] ||= "OpenBIS #{zample.perm_id}"
        assay = Assay.new(assay_params)
        assay.contributor = creator

        assay.external_asset = obis_asset
        assay
      end

      def createObisDataFile(obis_asset)

        dataset = obis_asset.content
        openbis_endpoint = obis_asset.seek_service

        df = DataFile.new(projects: [openbis_endpoint.project], title: "OpenBIS #{dataset.perm_id}",
                          license: openbis_endpoint.project.default_license)

        df.policy=openbis_endpoint.policy.deep_copy
        df.external_asset = obis_asset
        df
      end

      def sync_external_asset(obis_asset)

        entity = fetch_current_entity_version(obis_asset)

        errs = follow_dependent(obis_asset,entity) if should_follow_dependent(obis_asset)
        raise errs if errs

        obis_asset.content=entity
        obis_asset.save!
      end

      def should_follow_dependent(obis_asset)

        return false unless obis_asset.seek_entity.is_a? Assay
        obis_asset.sync_options[:link_datasets] == '1'
      end

      def fetch_current_entity_version(obis_asset)
        obis_asset.external_type.constantize.new(obis_asset.seek_service, obis_asset.external_id,true)
      end

      def follow_dependent(obis_asset, current_entity)

        puts 'following dependent'
        data_sets_ids = current_entity.dataset_ids || []
        associate_data_sets_ids(obis_asset.seek_entity, data_sets_ids, obis_asset.seek_service)

      end

      def associate_data_sets_ids(assay, data_sets_ids, endpoint)
        return nil if data_sets_ids.empty?

        data_sets = Seek::Openbis::Dataset.new(endpoint).find_by_perm_ids(data_sets_ids)
        associate_data_sets(assay, data_sets)
      end

      def associate_data_sets(assay, data_sets)

        external_assets = data_sets.map { |ds| OpenbisExternalAsset.find_or_create_by_entity(ds) }

        existing_files = external_assets.select { |es| es.seek_entity.is_a? DataFile }
                             .map { |es| es.seek_entity }

        new_files = external_assets.select { |es| es.seek_entity.nil? }
                        .map { |es| createObisDataFile(es) }

        saving_problems = false
        new_files.each { |df| saving_problems = true unless df.save }
        return 'Could not register all depended datasets' if saving_problems

        data_files = existing_files+new_files
        data_files.each { |df| assay.associate(df) }

        return nil

      end
    end
  end
end
