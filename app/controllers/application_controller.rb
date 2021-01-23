class ApplicationController < ActionController::Base
  include ApplicationHelper

  rescue_from CanCan::AccessDenied, with: :render_not_found_response_no_message
  rescue_from ActiveRecord::RecordInvalid, with: :render_unprocessable_entity_response
  rescue_from ActiveRecord::RecordNotFound, with: :render_not_found_response

  protect_from_forgery with: :exception
  # before_action :check_authorization
  before_action :security_check
  before_action :init_sync_info
  #before_action :init_user_stamp

  before_action :authorize_request

  after_action :set_csrf_cookie_for_ng
  after_action :broadcast_sync

  @@user = nil

  def current_user
    nil
  end

  def render_unprocessable_entity_response(exception)
    render json: exception.record.errors, status: :unprocessable_entity
  end

  def render_not_found_response(exception)
    render json: { error: exception.message }, status: :not_found
  end

  def render_not_found_response_no_message(exception)
    render json: { error: "Record not found" }, status: :not_found
  end


  def set_csrf_cookie_for_ng
    cookies['XSRF-TOKEN'] = form_authenticity_token if protect_against_forgery?
  end
  
  protected

  # In Rails 4.2 and above
  def verified_request?
    super || valid_authenticity_token?(session, request.headers['X-XSRF-TOKEN'])
  end

  def security_check
  	if !current_user
  		raise CanCan::AccessDenied
  	end
  	if !self.is_a? RailsAdmin::MainController
      begin
        model_class = controller_name.classify.constantize
      rescue
  	    model_class = @@security_check_model_class
      end
  	  if cannot? :access, model_class
  	 	  raise CanCan::AccessDenied
  	  end 
    end
  end


  def check
    if !yield
      raise CanCan::AccessDenied
    end
  end

  def init_sync_info
    @sync_info = []
  end

  def sync_on(selector, **args)
    if selector.respond_to? :each
      selector.each { |s| sync_on(s,**args) }
    else
      path = selector
      subpaths = args[:subpaths] 
      (@sync_info << path).uniq!
      path = subpath(path)
      while subpaths && path.present? 
        (@sync_info << path).uniq!
        path = subpath(path)
      end
    end
  end

  def subpath(path)
     path.split('/')[0..-2].join('/')
  end

  def broadcast_sync
    SyncChannel.broadcast_sync(@sync_info)
  end

  def init_user_stamp
    @@user = current_user
  end

  def self.user
    @@user
  end


  private

  def authorize_request 
    byebug
    AuthorizationService.new(request.headers).authenticate_request!
  rescue JWT::VerificationError, JWT::DecodeError
    render json: { errors: ['Not Authenticated'] }, status: :unauthorized
  end

end
