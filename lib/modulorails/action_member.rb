# frozen_string_literal: true

# Author: varaby_m@modulotech.fr
# this module helps member-based actions (show,edit,update,destroy) to find their target
# when target is not found it applies redirect (html) or returns 404 (json)
#
# example:
# u've got users_controller and want to update your user, so u put 'users/1'.
# in order to update user you first have to retrieve the model, then update it.
# i'm a fan of single business logic call per action. so there are two ways:
# 1. pass user_id to updater logic
# 2. pass loaded user record to updater logic
# i prefer #2. why not #1? that's the question.
# when we access some endpoint and it doesn't exist, who says 404? controller
# when we access some endpoint we don't have access to, who says 40X? controller
# than when we access member-based endpoint like edit or update, why should we handle it
# inside the business logic?
# moreover, when we add find logic to updater it breaks updater simplicity. updater should:
# filter params, update record, call some related stuff (callbacks, bound model updates).
# when updater starts finding record it should also: load record, handle not found case,
# add not found error. it becomes less flexible to reuse it - u should either reload model
# from db passing an id or add more complexity passing object and check: object or id.
# we can start finding record in the action, but it breaks the rule of 1 call per 1 action
# and adds business logic to controller action.
#
# correct usage in the given example
# class UsersController < ApplicationController
#
#   # adds before action to load user for update action
#   require_member! name: :user, only: :update
#
#   # member-based action #update
#   def update
#     # user is already here
#     Users::Update.call(user: user, params: params)
#   end
#
#   protected
#
#   # this method we should override
#   # finder class should respond to ::find method with 2 arguments
#   # first argument is member_id. member id is most cases is params[:id].
#   # or
#   # first argument may be a hash of conditions { lookup_code: 'asd', email: 'asd@asd' }
#   # second argument is finder options, that are required by it's object to initialize
#   def user_finder_class
#     Users::List
#   end
#
#   # second parameter passed to ::find method of user_finder_class
#   # it contains required_attributes for finder class, that can instantiate it
#   def user_options
#     { company: current_company }
#   end
#
# end
module Modulorails

  module ActionMember

    extend ActiveSupport::Concern

    module ClassMethods

      # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
      # @param [String, Symbol] name
      # @param [String, Symbol] param
      # @param [Class<Modulorails::ListWorker>] finder_class
      # @param [Hash] options
      def require_member!(name: :member, param: :id, finder_class:, **options)
        requirer = Module.new do
          extend ActiveSupport::Concern

          included do
            # add before filter to find member
            before_action :"require_#{name}!", options
          end

          protected

          # reader for member
          attr_reader :"#{name}"

          # member id interface
          # @return [String, Integer]
          define_method :"#{name}_id" do
            params.require(param)
          end

          # member record class
          # @return [Class<ApplicationRecord>]
          define_method :"#{name}_class" do
            finder_class.model
          end

          # member find options
          # @return [Hash]
          define_method :"#{name}_options" do
            {}
          end

          # method returns where to redirect when no member found
          # @return [Hash, Symbol, String]
          define_method :"no_#{name}_redirect" do
            respond_to?(:index) ? { action: :index } : :back
          end

          # no member error
          # @return [String]
          define_method :"#{name}_error" do
            I18n.t('action_member.not_found',
                   model: send("#{name}_class").model_name.human, id: send("#{name}_id"))
          end

          private

          # before action to find action member
          define_method :"require_#{name}!" do
            # member id
            # find action member
            instance_variable_set(
              :"@#{name}",
              finder_class.find(send("#{name}_id"), send("#{name}_options"))
            )
            # return if found
            return if send(name)

            # respond with error
            respond_to_error(send("#{name}_error"), :not_found, send("no_#{name}_redirect"))
          end
        end

        # include module into current controller
        include requirer
      end
      # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

    end

    def respond_to_error(error, status=:internal_server_error, redirect=:back)
      respond_to do |format|
        # in case of html format
        format.html do
          # put message to flash
          flash[:error] = error
          # and redirect
          redirect_to redirect
        end
        # in case of api request
        format.json do
          # render http status and error message in the json body
          render status: status, json: { error: error }
        end
        # allow to override
        yield(format) if block_given?
        # in case of any other request
        format.any do
          head :not_found
        end
      end
    end

  end

end

action_member_translations =
  File.expand_path('../../config/locales/action_member.en.yml', __dir__)
I18n.backend.send(:load_file, action_member_translations)
