# coding: utf-8
# Filters added to this controller apply to all controllers in the application.
# Likewise, all the methods added will be available for all controllers.

require 'authenticated_system'

class ApplicationController < ActionController::Base
  include Seek::Errors::ControllerErrorHandling
  include Seek::EnabledFeaturesFilter
  include Recaptcha::Verify

  include CommonSweepers
  @is_json = false

  before_filter :log_extra_exception_data

  # if the logged in user is currently partially registered, force the continuation of the registration process
  before_filter :partially_registered?

  after_filter :log_event

  include AuthenticatedSystem

  around_filter :with_current_user

  rescue_from 'ActiveRecord::RecordNotFound', with: :render_not_found_error
  rescue_from 'ActiveRecord::UnknownAttributeError', with: :render_unknown_attribute_error

  before_filter :project_membership_required, only: [:create, :new]

  before_filter :restrict_guest_user, only: [:new, :edit, :batch_publishing_preview]
  #before_filter :process_params, :only=>[:edit, :update, :destroy, :create, :new]
  before_filter :set_is_json   #, :only=>[:edit, :update, :destroy, :create, :new]
  before_filter :check_illegal_id, :only=>[:create]
  # after_filter :unescape_response

  before_filter :convert_json_params

  helper :all

  layout Seek::Config.main_layout


  def with_current_user
    User.with_current_user current_user do
      yield
    end
  end

  def current_person
    current_user.try(:person)
  end

  def partially_registered?
    redirect_to register_people_path if current_user && !current_user.registration_complete?
  end

  def strip_root_for_xml_requests
    # intended to use as a before filter on requests that lack a single root model.
    # XML requests are required to have a single root node. This assumes the root node
    # will be named xml. Turns a params hash like.. {:xml => {:param_one => "val", :param_two => "val2"}}
    # into {:param_one => "val", :param_two => "val2"}

    # This should probably be used with prepend_before_filter, since some filters might need this to happen so they can check params.
    # see sessions controller for an example usage
    params[:xml].each { |k, v| params[k] = v } if request.format.xml? && params[:xml]
  end

  def set_no_layout
    self.class.layout nil
  end

  def base_host
    request.host_with_port
  end

  def set_is_json
    @is_json = (request.format.json?)
  end

  def api_version
    @default = 1
    version_re_arr = [/version=(?<v>.+?)/, /api.v(?<v>\d+?)\+json/]
    version_re_arr.each do |re|
      v_match = request.headers['Accept'].match(re)
      if (v_match  != nil)
        @version = v_match[:v]
        break
      end
    end
    @version ||= @default
    puts "api version: ", @version
  end

  def is_current_user_auth
    begin
      @user = User.where(['id = ?', current_user.try(:id)]).find(params[:id])
    rescue ActiveRecord::RecordNotFound
      error('User not found (id not authorized)', 'is invalid (not owner)')
      return false
    end

    unless @user
      error('User not found (or not authorized)', 'is invalid (not owner)')
      return false
    end
  end

  def is_user_admin_auth
    unless User.admin_logged_in?
      error('Admin rights required', 'is invalid (not admin)')
      return false
    end
    true
  end

  def can_manage_announcements?
    User.admin_logged_in?
  end

  def logout_user
    current_user.forget_me if logged_in?
    cookies.delete :auth_token
    reset_session
  end

  # MERGENOTE - put back for now, but needs modularizing, refactoring, and possibly replacing
  def resource_in_tab
    resource_type = params[:resource_type]
    view_type = params[:view_type]
    scale_title = params[:scale_title] || ''

    if params[:actions_partial_disable] == 'true'
      actions_partial_disable = true
    else
      actions_partial_disable = false
    end

    # params[:resource_ids] is passed as string, e.g. "id1, id2, ..."
    resource_ids = (params[:resource_ids] || '').split(',')
    clazz = resource_type.constantize
    resources = clazz.where(id: resource_ids)
    if clazz.respond_to?(:authorized_partial_asset_collection)
      authorized_resources = clazz.authorized_partial_asset_collection(resources, 'view')
    elsif resource_type == 'Project' || resource_type == 'Institution'
      authorized_resources = resources
    elsif resource_type == 'Person' && Seek::Config.is_virtualliver && current_user.nil?
      authorized_resources = []
    else
      authorized_resources = resources.select(&:can_view?)
    end

    render partial: 'assets/resource_in_tab',
           locals: { resources: resources,
                     scale_title: scale_title,
                     authorized_resources: authorized_resources,
                     view_type: view_type,
                     actions_partial_disable: actions_partial_disable }
  end

  private

  def restrict_guest_user
    if current_user && current_user.guest?
      flash[:error] = 'You cannot perform this action as a Guest User. Please sign in or register for an account first.'
      if !request.env['HTTP_REFERER'].nil?
        redirect_to :back
      else
        redirect_to main_app.root_path
      end
    end
  end

  private

  def project_membership_required
    unless User.logged_in_and_member? || User.admin_logged_in?
      flash[:error] = 'Only members of known projects, institutions or work groups are allowed to create new content.'
      respond_to do |format|
        format.html do
          object = eval('@' + controller_name.singularize)
          if !object.nil? && object.try(:can_view?)
            redirect_to object
          else
            path = nil
            begin
              path = eval("main_app.#{controller_name}_path")
            rescue NoMethodError => e
              logger.error("No path found for controller - #{controller_name}")
              path = main_app.root_path
            end
            redirect_to path
          end
        end
        format.json { render json: {"title": "Unauthorized", "detail": flash[:error].to_s}, status: :unauthorized}
      end
    end
  end

  alias_method :project_membership_required_appended, :project_membership_required

  # used to suppress elements that are for virtualliver only or are still currently being worked on
  def virtualliver_only
    unless Seek::Config.is_virtualliver
      error('This feature is is not yet currently available', 'invalid route')
      return false
    end
  end

  def check_allowed_to_manage_types
    unless Seek::Config.type_managers_enabled
      error('Type management disabled', '...')
      return false
    end
    if current_user
      if current_user.can_manage_types?
        return true
      else
        error('Admin rights required to manage types', '...')
        return false
      end
    else
      error('You need to login first.', '...')
      return false
    end
  end

  def error(notice, _message)
    flash[:error] = notice

    respond_to do |format|
      format.html { redirect_to root_url }
      format.json { redirect_to root_url }
    end
  end

  # required for the Savage Beast
  def admin?
    User.admin_logged_in?
  end

  # handles finding an asset, and responding when it cannot be found. If it can be found the item instance is set (e.g. @project for projects_controller)
  def find_requested_item
    name = controller_name.singularize
    object = name.camelize.constantize.find_by_id(params[:id])
    if object.nil?
      respond_to do |format|
        flash[:error] = "The #{name.humanize} does not exist!"
        format.rdf { render text: 'Not found', status: :not_found }
        format.xml { render text: '<error>404 Not found</error>', status: :not_found }
        format.json { render json: {"title": "Not found", status: :not_found}, status: :not_found }
        format.html { redirect_to eval "#{controller_name}_path" }
      end
    else
      eval "@#{name} = object"
    end
  end

  # handles finding and authorizing an asset for all controllers that require authorization, and handling if the item cannot be found
  def find_and_authorize_requested_item
    name = controller_name.singularize
    privilege = Seek::Permissions::Translator.translate(action_name)

    return if privilege.nil?

    object = controller_name.classify.constantize.find(params[:id])

    if is_auth?(object, privilege)
      eval "@#{name} = object"
      params.delete :policy_attributes unless object.can_manage?(current_user)
    else
      respond_to do |format|
        format.html do
          case privilege
          when :publish, :manage, :edit, :download, :delete
            if current_user.nil?
              flash[:error] = "You are not authorized to #{privilege} this #{name.humanize}, you may need to login first."
            else
              flash[:error] = "You are not authorized to #{privilege} this #{name.humanize}."
            end
            redirect_to(eval("#{controller_name.singularize}_path(#{object.id})"))
          else
            render template: 'general/landing_page_for_hidden_item', locals: { item: object }, status: :forbidden
          end
        end
        format.rdf { render text: "You may not #{privilege} #{name}:#{params[:id]}", status: :forbidden }
        format.xml { render text: "You may not #{privilege} #{name}:#{params[:id]}", status: :forbidden }
        format.json {
          render json: {"title": "Forbidden", "detail": "You may not #{privilege} #{name}:#{params[:id]}"}, status: :forbidden
        }
      end
      return false
    end
  end

  def auth_to_create
    unless controller_name.classify.constantize.can_create?
      error('You do not have permission', 'No permission')
      return false
    end
  end

  def render_not_found_error
    respond_to do |format|
      format.html do
        User.with_current_user current_user do
          render template: 'general/landing_page_for_not_found_item', status: :not_found
        end
      end

      format.rdf { render text: 'Not found', status: :not_found }
      format.xml { render text: '<error>404 Not found</error>', status: :not_found }
      format.json { render json: {"title": "Not found", status: :not_found}, status: :not_found }
    end
    false
  end

  def render_unknown_attribute_error(e)
    respond_to do |format|
      format.json {
        render json: {error: e.message, status: :unprocessable_entity}, status: :unprocessable_entity
      }
      format.all {
        render text: e.message, status: :unprocessable_entity
      }
    end
  end

  def is_auth?(object, privilege)
    if object.can_perform?(privilege)
      true
    elsif params[:code] && [:view, :download].include?(privilege)
      object.auth_by_code?(params[:code])
    else
      false
    end
  end

  def log_event
    # FIXME: why is needed to wrap in this block when the around filter already does ?
    User.with_current_user current_user do
      controller_name = self.controller_name.downcase
      action = action_name.downcase

      object = object_for_request

      object = current_user if controller_name == 'sessions' # logging in and out is a special case

      # don't log if the object is not valid or has not been saved, as this will a validation error on update or create
      return if object_invalid_or_unsaved?(object)

      case controller_name
      when 'sessions'
        if %w(create destroy).include?(action)
          ActivityLog.create(action: action,
                             culprit: current_user,
                             controller_name: controller_name,
                             activity_loggable: object,
                             user_agent: request.env['HTTP_USER_AGENT'])
        end
      when 'sweeps', 'runs'
        if %w(show update destroy download).include?(action)
          ref = object.projects.first
        elsif action == 'create'
          ref = object.workflow
        end

        check_log_exists(action, controller_name, object)
        ActivityLog.create(action: action,
                           culprit: current_user,
                           referenced: ref,
                           controller_name: controller_name,
                           activity_loggable: object,
                           data: object.title,
                           user_agent: request.env['HTTP_USER_AGENT'])
        break
      when 'people', 'projects', 'institutions'
        if %w(show create update destroy).include?(action)
          ActivityLog.create(action: action,
                             culprit: current_user,
                             controller_name: controller_name,
                             activity_loggable: object,
                             data: object.title,
                             user_agent: request.env['HTTP_USER_AGENT'])
        end
      when 'search'
        if action == 'index'
          ActivityLog.create(action: 'index',
                             culprit: current_user,
                             controller_name: controller_name,
                             user_agent: request.env['HTTP_USER_AGENT'],
                             data: { search_query: object, result_count: @results.count })
        end
      when 'content_blobs'
        # action download applies for normal download
        # action inline_view applies for viewing image and pdf file in browser
        action = 'inline_view' if action == 'view_content' # view pdf
        action = 'inline_view' if action == 'download' && params['disposition'].to_s == 'inline' # view image

        # when viewing pdf content, first it goes to 'view_content' action, then 'download' action, with intent = 'inline_view'
        # so do not log the 'download' action in this case
        # just making a fake action here
        action = 'feed_pdf_inline_view' if action == 'download' && params['intent'].to_s == 'inline_view'
        if %w(download inline_view).include?(action)
          activity_loggable = object.asset
          ActivityLog.create(action: action,
                             culprit: current_user,
                             referenced: object,
                             controller_name: controller_name,
                             activity_loggable: activity_loggable,
                             user_agent: request.env['HTTP_USER_AGENT'],
                             data: activity_loggable.title)
        end
      when *Seek::Util.authorized_types.map { |t| t.name.underscore.pluralize.split('/').last } # TODO: Find a nicer way of doing this...
        action = 'create' if action == 'upload_for_tool'
        action = 'update' if action == 'new_version'
        action = 'inline_view' if action == 'explore'
        if %w(show create update destroy download inline_view).include?(action)
          check_log_exists(action, controller_name, object)
          ActivityLog.create(action: action,
                             culprit: current_user,
                             referenced: object.projects.first,
                             controller_name: controller_name,
                             activity_loggable: object,
                             data: object.title,
                             user_agent: request.env['HTTP_USER_AGENT'])
        end
      end

      expire_activity_fragment_cache(controller_name, action)
    end
  end

  def object_invalid_or_unsaved?(object)
    object.nil? || (object.respond_to?('new_record?') && object.new_record?) || (object.respond_to?('errors') && !object.errors.empty?)
  end

  # determines and returns the object related to controller, e.g. @data_file
  def object_for_request
    c = controller_name.downcase

    eval('@' + c.singularize)
  end

  def expire_activity_fragment_cache(controller, action)
    if action != 'show'
      @@auth_types ||= Seek::Util.authorized_types.collect { |t| t.name.underscore.pluralize }
      if action == 'download'
        expire_download_activity
      elsif action == 'create' && controller != 'sessions'
        expire_create_activity
      elsif action == 'destroy' && controller != 'sessions'
        expire_create_activity
        expire_download_activity
      elsif action == 'update' && @@auth_types.include?(controller) # may have had is permission changed
        expire_create_activity
        expire_download_activity
        expire_resource_list_item_action_partial
      end
    end
  end

  def check_log_exists(action, controllername, object)
    if action == 'create'
      a = ActivityLog.where(
        activity_loggable_type: object.class.name,
        activity_loggable_id: object.id,
        controller_name: controllername,
        action: 'create').first

      logger.error("ERROR: Duplicate create activity log about to be created for #{object.class.name}:#{object.id}") unless a.nil?
    end
  end

  # Strips any unexpected filter, which protects us from shennanigans like params[:filter] => {:destroy => 'This will destroy your data'}
  def strip_unpermitted_filters(filters)
    # placed this in a separate method so that other controllers could override it if necessary
    permitted = Seek::Util.persistent_classes.select { |c| c.respond_to? :find_by_id }.map { |c| c.name.underscore }
    filters.select { |filter| permitted.include?(filter.to_s) }
  end

  def apply_filters(resources)
    filters = params[:filter] || {}

    # translate params that are send as an _id, like project_id=12 - which will usually be a consequence of nested routing
    params.keys.each do |key|
      filters[key.gsub('_id', '')] = params[key] if key.end_with?('_id')
    end

    filters = strip_unpermitted_filters(filters)

    if filters.size > 0
      params[:page] ||= 'all'
      params[:filtered] = true
      resources.select do |res|
        filters.all? do |filter, value|
          filter = filter.to_s
          klass = filter.camelize.constantize
          value = klass.find value.to_i

          detect_for_filter(filter, res, value)
        end
      end
    else
      resources
    end
  end

  def detect_for_filter(filter, resource, value)
    case
    when resource.respond_to?(filter.pluralize)
      resource.send(filter.pluralize).include? value
    when resource.respond_to?("related_#{filter.pluralize}")
      resource.send("related_#{filter.pluralize}").include?(value)
    when resource.respond_to?(filter)
      resource.send(filter) == value
    else
      false
    end
  end

  # checks if a captcha has been filled out correctly, if enabled, and returns false if not
  def check_captcha
    if Seek::Config.recaptcha_setup?
      verify_recaptcha
    else
      true
    end
  end

  def append_info_to_payload(payload)
    super
    payload[:user_agent] = request.user_agent
  end

  def log_extra_exception_data
    request.env['exception_notifier.exception_data'] = {
      current_logged_in_user: current_user
    }
  end

  def redirect_to_sign_up_when_no_user
    redirect_to signup_path if User.count == 0
  end

  def check_illegal_id
    begin
      Rails.logger.info("checking illegal ID")
      if !params[:id].nil?
        raise ArgumentError.new('A POST request is not allowed to specify an id')
      end
    rescue ArgumentError => e
      render json: {error: e.message, status: :forbidden}, status: :forbidden
    end
  end

  #process JSONAPI params into params itself, so it can be used normally with create, update, etc.
  def process_params()

    resource = controller_name.singularize

    #check for JSONAPI
    if params.key?("data")
      params[resource] = params[:data][:attributes]

      #initialize
      params[:relationships].each do |r,info|
        params[resource][r.to_s+"_ids"] = []
      end

      #fill up related resource ids in params[resource][related_ids] from the meta section in relationships
      #This makes sense when a user creates his own file to upload, and does not know IDs of resources, plus
      #creating associated branches within data in JSONAPI format is adding too much complexity and user-unfriendly standards.
      params[:relationships].each do |r,info|
        related_entity = r.capitalize.constantize.where(info[:meta]).first
        params[resource][r.to_s+"_ids"] << related_entity.id if related_entity
        puts "related entity: ", related_entity
      end

      # #2nd way: fill up from associated resources (e.g. from an exported json)
      # # TO DO: decide if this is the final input/output format
      # # problem : not everything should exist for every resource, e.g associated people are creators of an investigation, but not a project
      # begin
      #   params[:data][:relationships][:associated][:data].each do |assoc_data|
      #     puts "associated ====> ", assoc_data
      #     key = assoc_data[:type].singularize + "_ids"
      #     params[resource][key] = [] if (params[resource][key] == nil)
      #     params[resource][key] << assoc_data[:id].to_i
      #   end
      #
      # rescue NoMethodError
      #   puts "no associated stuff"
      # end


      #Creators
      creators_arr = []
      params[resource][:creators].each do |cr|
        the_person = Person.where(email: cr).first
        creators_arr << the_person if the_person
      end
      params[resource][:creators] = creators_arr
    end
  end

  # Non-ascii-characters are escaped, even though the response is utf-8 encoded.
  # This method will convert the escape sequences back to characters, i.e.: "\u00e4" -> "ä" etc.
  # from https://stackoverflow.com/questions/5123993/json-encoding-wrongly-escaped-rails-3-ruby-1-9-2
  # by steffen.brinkmann@h-its.org
  # 2017-04-18
#  def unescape_response()
#    response_body[0].gsub!(/\\u([0-9a-z]{4})/) { |s|
#      [$1.to_i(16)].pack("U")
#    }
#  end

  def policy_params
    params.slice(:policy_attributes).permit(
        policy_attributes: [:access_type,
                            { permissions_attributes: [:access_type,
                                                       :contributor_type,
                                                       :contributor_id] }])[:policy_attributes] || {}
  end

  def convert_json_params
    if @is_json
      hacked_params = flatten_relationships(params)
      params[controller_name.classify.downcase.to_sym] =
          ActiveModelSerializers::Deserialization.jsonapi_parse(hacked_params)
    end
  end

  def flatten_relationships(original_params)
    replacements = {}
    begin
      rels = original_params[:data][:relationships]
      assoc = rels[:associated]
      assoc_relationships = assoc[:data]
      assoc_relationships.each do |assoc_rel|
        the_type = assoc_rel["type"]
        the_id = assoc_rel["id"]
        if !replacements.key?(the_type)
          replacements[the_type] = {}
          replacements[the_type][:data] = []
        end
        replacements[the_type][:data].push({:type => the_type, :id => the_id})
      end
      rels.delete(:associated)
      original_params[:data][:relationships].merge!(ActionController::Parameters.new(replacements))
    rescue Exception
    end
    original_params
  end

end
