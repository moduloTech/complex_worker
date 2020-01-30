# frozen_string_literal: true

require 'modulorails/action_member'
require 'action_controller/metal/strong_parameters'

RSpec.describe Modulorails::ActionMember, type: :model do
  let(:fake_finder) do
    Class.new(Modulorails::ListWorker) do
      model FakeUser
    end
  end

  let(:options) do
    { name: :user, param: :user_id, finder_class: fake_finder }
  end

  let(:fake_controller) do
    opts = options
    Class.new do
      class << self

        attr_reader :before_actions

        def before_action(name, *)
          @before_actions ||= []
          @before_actions << ->(instance) { instance.send(name) }
        end

      end

      include Modulorails::ActionMember

      require_member! opts

      attr_reader :rendered, :params, :format

      def initialize(params, format=:json)
        @rendered = []
        @params = ActionController::Parameters.new(params)
        @format = format.to_sym
      end

      def index
        self.class.before_actions.each do |action|
          action.call(self)
          break if rendered
        end
        self
      end

      def redirect_to(*args)
        @rendered += [:redirect, *args]
      end

      def head(status)
        @rendered += [:head, { status: status }]
      end

      def render(*args)
        @rendered += [:render, *args]
      end

      def flash
        @flash ||= Class.new {
          def initialize(rendered)
            @rendered = rendered
          end

          define_method :[]= do |key, value|
            @rendered.push(:flash, key => value)
          end
        }.new(rendered)
      end

      def respond_to
        formats = {}

        yield(Class.new do
          %i[html json pdf js all].each do |m|
            define_singleton_method m do |&block|
              formats[m] = block
            end
          end

          define_singleton_method :any do |*fmts, &block|
            fmts.each { |m| formats[m] = block }
          end
        end)

        format_renderer = formats[format] || raise(ActionController::UnknownFormat)
        format_renderer.call
      end
    end
  end

  let(:user) { FakeUser.create(email: 'asd@asd') }
  let(:params) do
    { user_id: user.id }
  end
  let(:format) { :json }

  subject { fake_controller.new(params, format).index.rendered }

  it { is_expected.to be_empty }

  context 'when param is missing' do
    let!(:params_remove_user_id) { params.delete(:user_id) }

    it { expect { subject }.to raise_error ActionController::ParameterMissing }
  end

  context 'when member is not found' do
    let!(:params_wrong_user_id) { params[:user_id] = -1 }

    it 'renders not found error' do
      is_expected.to eq(
        [:render, { json: { error: 'Fake user(-1) was not found.' }, status: :not_found }]
      )
    end

    context 'when format html' do
      let(:format) { :html }

      it 'redirects with flash message' do
        is_expected.to eq(
          [:flash, { error: 'Fake user(-1) was not found.' },
           :redirect, { action: :index }]
        )
      end
    end
  end
end
