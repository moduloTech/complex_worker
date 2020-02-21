# frozen_string_literal: true

require 'modulorails/complex_worker'

RSpec.describe Modulorails::ComplexWorker do
  SomeWorker = Class.new(Modulorails::BasicWorker) do
    require_attributes :user, :params

    def call
      user.update(params)
      user
    end
  end

  subject do
    Class.new(Modulorails::ComplexWorker) {
      require_attributes :p1, :p2, :u1, :u2
      require_attributes :p3, :u3, optional: true

      step SomeWorker, p1: :params, u1: :user
      step SomeWorker, p2: :params, u2: :user
      step SomeWorker, p3: :params, u3: :user, if: ->(_w, options) { options[:u3].present? }

      def self.call(options)
        @in_transaction = options.delete(:in_transaction) if options.key?(:in_transaction)
        @mode = options.delete(:mode) if options.key?(:mode)
        super
      end

    }.call(options)
  end

  let(:user1) { FakeUser.create!(email: 'asd', first_name: 'asd', last_name: 'asd') }
  let(:user2) { FakeUser.create!(email: 'asd1@asd1', first_name: 'asd1', last_name: 'asd1') }
  let(:user3) { FakeUser.create!(email: 'asd2', first_name: 'asd2', last_name: 'asd2') }
  let(:email) { 'ddd@ddd' }
  let(:in_transaction) { true }
  let(:mode) { :rollback_end }
  let(:options) do
    { u1: user1, p1: { first_name: 'ddd' }, u2: user2, p2: { email: email },
      u3: user3, p3: { last_name: 'dd3' }, in_transaction: in_transaction, mode: mode }
  end

  it { expect { subject }.to change { user1.reload.first_name }.to('ddd') }
  it { expect { subject }.to change { user2.reload.email }.to('ddd@ddd') }
  it { expect { subject }.to change { user3.reload.last_name }.to('dd3') }

  context 'when one worker fails' do
    let(:email) { nil }

    it { expect { subject }.not_to change { user1.reload.first_name }.from('asd') }
    it { expect { subject }.not_to change { user2.reload.email }.from('asd1@asd1') }
    it { expect { subject }.not_to change { user3.reload.last_name }.from('asd2') }
    it { expect { subject }.to change { user3.last_name }.from('asd2').to('dd3') }

    context 'when without transaction' do
      let(:in_transaction) { false }

      it { expect { subject }.to change { user1.reload.first_name }.to('ddd') }
      it { expect { subject }.not_to change { user2.reload.email }.from('asd1@asd1') }
      it { expect { subject }.to change { user3.reload.last_name }.to('dd3') }
    end

    context 'when mode is :rollback_any' do
      let(:mode) { :rollback_any }

      it { expect { subject }.not_to change { user3.reload.last_name }.from('asd2') }
      it { expect { subject }.not_to change { user3.last_name }.from('asd2') }
    end
  end
end
