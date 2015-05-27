module AssetsHelper
  include ApplicationHelper

  #the prefix used on some field id's, e.g. data_files_data_url
  def asset_field_prefix
    controller_name.downcase.singularize.underscore
  end

  def request_request_label resource
    icon_filename=icon_filename_for_key("message")
    resource_type=text_for_resource(resource)
    image_tag(icon_filename, :alt => "Request", :title => "Request") + " Request #{resource_type}"
  end

  def filesize_as_text content_blob
    size=content_blob.nil? ? 0 : content_blob.filesize
    if size.nil?
      html = "<span class='none_text'>Unknown</span>"
    else
      html = number_to_human_size(size)
    end
    html.html_safe
  end

  def item_description item_description, options={}
    render :partial => "assets/item_description", :object => item_description, :locals => options
  end

  #returns all the classes for models that return true for is_asset?
  def asset_model_classes
    @@asset_model_classes ||= Seek::Util.persistent_classes.select do |c|
      !c.nil? && c.is_asset?
    end
  end

  def publishing_item_param item
    "publish[#{item.class.name}][#{item.id}]"
  end

  def text_for_resource resource_or_text
    if resource_or_text.is_a?(String)
      text = resource_or_text.underscore.humanize
    else
      resource_type = resource_or_text.class.name
      if resource_or_text.is_a?(Assay)
        text = resource_or_text.is_modelling? ? t("assays.modelling_analysis") : t("assays.assay")
      elsif resource_or_text.is_a?(Specimen)
        text = t('biosamples.sample_parent_term')
      elsif !(translated = translate_resource_type(resource_type)).include?("translation missing")
        text = translated
      else
        text = resource_type.underscore.humanize
      end
    end
    text
  end

  def get_original_model_name(model)
    class_name = model.class.name
    if class_name.end_with?("::Version")
      class_name = class_name.split("::")[0]
    end
    class_name
  end

  def download_resource_path(resource, code=nil)
    if resource.class.name.include?("::Version")
      polymorphic_path(resource.parent, :version => resource.version, :action => :download, :code => params[:code])
    else
      polymorphic_path(resource, :action => :download, :code => params[:code])
    end
  end

  #returns true if this permission should not be able to be removed from custom permissions
  #it indicates that this is the management rights for the current user.
  #the logic is that true is returned if the current_user is the contributor of this permission, unless that person is also the contributor of the asset
  def prevent_manager_removal(resource, permission)
    permission.access_type==Policy::MANAGING && permission.contributor==current_user.person && resource.contributor != current_user
  end

  def show_resource_path(resource)
    path = ""
    if resource.class.name.include?("::Version")
      path = polymorphic_path(resource.parent, :version => resource.version)
    else
      path = polymorphic_path(resource)
    end
    return path
  end

  def edit_resource_path(resource)
    path = ""
    if resource.class.name.include?("::Version")
      path = edit_polymorphic_path(resource.parent)
    else
      path = edit_polymorphic_path(resource)
    end
    return path
  end

  #Resource hash for lazy loaded tabs, key: resource_type, value: resource
  #Each hash value
  def resource_hash_lazy_load resource
    resource_hash = {}
    all_related_items_hash = collect_related_items(resource)
    all_related_items_hash.each_key do |resource_type|
      all_related_items_hash[resource_type][:items].uniq!
      all_related_items_hash[resource_type][:items].compact!
      unless all_related_items_hash[resource_type][:items].empty?
        resource_hash[resource_type] = all_related_items_hash[resource_type][:items]
      end
    end
    resource_hash
  end

  #Get a hash of appropriate related resources for the given resource. Also returns a hash of hidden resources
  def get_related_resources(resource, limit=nil)
    return resource_hash_lazy_load(resource) if Seek::Config.tabs_lazy_load_enabled
    name = resource.class.name.split("::")[0]

    related = collect_related_items(resource)

    #Authorize
    authorize_related_items(related)

    order_related_items(related)

    #Limit items viewable, and put the excess count in extra_count
    related.each_key do |key|
      if limit && related[key][:items].size > limit && ["Project", "Investigation", "Study", "Assay", "Person", "Specimen", "Sample", "Run", "Workflow", "Sweep"].include?(resource.class.name)
        related[key][:extra_count] = related[key][:items].size - limit
        related[key][:items] = related[key][:items][0...limit]
      end
    end

    return related
  end

  def relatable_types
    {"Person" => {}, "Project" => {}, "Institution" => {}, "Investigation" => {},
     "Study" => {}, "Assay" => {}, "Specimen" => {}, "Sample" => {}, "DataFile" => {}, "Model" => {}, "Sop" => {}, "Publication" => {}, "Presentation" => {}, "Event" => {},
     "Workflow" => {}, "TavernaPlayer::Run" => {}, "Sweep" => {}, "Strain" => {}
    }

  end

  def related_items_method(resource, item_type)
    if item_type == "TavernaPlayer::Run"
      method_name = 'runs'
    else
      method_name = item_type.underscore.pluralize
    end

    if resource.respond_to? method_name
      resource.send method_name
    elsif resource.respond_to? "related_#{method_name}"
      resource.send "related_#{method_name}"
    elsif resource.respond_to? "related_#{method_name.singularize}"
      Array(resource.send("related_#{method_name.singularize}"))
    elsif resource.respond_to? method_name.singularize
      Array(resource.send(method_name.singularize))
    else
      []
    end
  end

  def order_related_items(related)
    related.each do |key, res|
      res[:items].sort! { |item, item2| item2.updated_at <=> item.updated_at }
    end
  end

  def authorize_related_items(related)
    related.each do |key, res|
      res[:items].uniq!
      res[:items].compact!
      unless res[:items].empty?
        total_count = res[:items].size
        if key == 'Project' || key == 'Institution'
          res[:hidden_count] = 0
        elsif key == 'Person'
          if Seek::Config.is_virtualliver && User.current_user.nil?
            res[:items] = []
            res[:hidden_count] = total_count
          else
            res[:hidden_count] = 0
          end
        else
          total = res[:items]
          res[:items] = key.constantize.authorize_asset_collection res[:items], 'view', User.current_user
          res[:hidden_count] = total_count - res[:items].size
          res[:hidden_items] = total - res[:items]
        end
      end
    end
  end


  def collect_related_items(resource)
    related = relatable_types.delete_if { |k, v| k==resource.class.name }

    related.each_key do |type|
      related[type][:items] = related_items_method(resource, type)
      related[type][:hidden_items] = []
      related[type][:hidden_count] = 0
      related[type][:extra_count] = 0
    end

    related
  end

  #provides a list of assets, according to the class, that are authorized according the 'action' which defaults to view
  #if projects is provided, only authorizes the assets for that project
  # assets are sorted by title except if they are projects and scales (because of hierarchies)
  def authorised_assets asset_class, projects=nil, action="view"
    assets = asset_class.all_authorized_for action, User.current_user,projects
    assets = assets.sort_by &:title if !assets.blank? && !["Project", "Scale"].include?(assets.first.class.name)
    assets
  end

  def asset_buttons asset, version=nil
    render :partial => "assets/asset_buttons", :locals => {:asset => asset, :version => version}
  end

  def asset_version_links asset_versions
    asset_version_links = []
    asset_versions.select(&:can_view?).each do |asset_version|
      asset_name = asset_version.class.name.split('::').first.underscore
      asset_version_links << link_to(asset_version.title, eval("#{asset_name}_path(#{asset_version.send("#{asset_name}_id")})") + "?version=#{asset_version.version}")
    end
    asset_version_links
  end

  #code is for authorization of temporary link
  def can_download_asset? asset, code=params[:code], can_download=asset.can_download?
    can_download || (code && asset.auth_by_code?(code))
  end

  #code is for authorization of temporary link
  def can_view_asset? asset, code=params[:code], can_view=asset.can_view?
    can_view || (code && asset.auth_by_code?(code))
  end

  def asset_link_url asset
    asset.single_content_blob.try(:url)
  end

  def download_or_link_button asset, download_path, link_url, human_name=nil, opts = {}
    download_button = icon_link_to('Download', 'download', download_path, opts)
    link_button_or_nil = link_url ? icon_link_to('Link', 'download', link_url, opts.merge({:target => 'blank'})) : nil
    return asset.content_blob.show_as_external_link? ? link_button_or_nil : download_button if asset.respond_to?(:content_blob)
    return asset.content_blobs.detect { |blob| !blob.show_as_external_link? } ? download_button : link_button_or_nil if asset.respond_to?(:content_blobs)
  end

  def view_content_button asset
    render :partial => "assets/view_content", :locals => {:content_blob => asset.single_content_blob, :button_style => true} if asset.single_content_blob && !asset.single_content_blob.show_as_external_link?
  end

  def doi_link doi
    link_to doi,"https://dx.doi.org/#{doi}"
  end

  def sharing_text(item)
    if item.private?
      sharing_text = "This item is <span style='color: red; font-weight: bold;'>Private</span> (only you can view it)"
    elsif item.is_published?
      sharing_text = "This item is <span style='color: green; font-weight: bold;'>Published</span> (all visitors, even without a login, may view/access this item)"
    elsif item.public?
      sharing_text = "This item is <span style='color: green; font-weight: bold;'>Public</span> visible (all visitors, even without a login, may view this item)"
    else
      sharing_text = "This item is <span style='font-weight: bold;'>Shared</span>, but not with all visitors to this site"
    end
    sharing_text.html_safe
  end

end
