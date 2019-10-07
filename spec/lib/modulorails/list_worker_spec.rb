# frozen_string_literal: true

require 'modulorails/list_worker'

# Author: varaby_m@modulotech.fr
RSpec.describe Modulorails::ListWorker do
  let(:options) { {} }

  let(:klass) do
    Class.new(described_class) {
      def model
        FakeUser
      end
    }
  end

  subject(:base) do
    klass.call(options)
  end

  subject(:sql) { base.relation.to_sql }

  it { expect(base).to be_an_instance_of klass }

  it 'builds the relation' do
    expect(sql).to eq(
      'SELECT "fake_users".* FROM "fake_users" ORDER BY "fake_users"."id" LIMIT 10 OFFSET 0'
    )
  end

  context 'when filter given' do
    let(:options) { { filter: { first_name: 'asd' } } }

    it 'applies filter' do
      expect(sql).to include 'WHERE "fake_users"."first_name" = \'asd\''
    end
  end

  context 'when page given' do
    let(:options) { { page: 2 } }

    it 'applies offset' do
      expect(sql).to include "OFFSET #{Modulorails::ListWorker::DEFAULT_PER_PAGE}"
    end
  end

  context 'when per_page given' do
    let(:options) { { per_page: 2 } }

    it 'applies limit' do
      expect(sql).to include 'LIMIT 2'
    end
  end

  context 'when order_field given' do
    let(:options) { { order_field: :last_name } }

    it 'applies order' do
      expect(sql).to include 'ORDER BY "fake_users"."last_name"'
    end
  end

  context 'when order_direction given' do
    let(:options) { { order_direction: :desc } }

    it 'applies order direction' do
      expect(sql).to include 'ORDER BY "fake_users"."id" DESC'
    end

    context 'when order_direction invalid' do
      let(:options) { { order_direction: 'asc) UNION (DELETE FROM USERS)' } }

      it 'applies order direction :asc' do
        expect(base.send(:order_direction)).to eq 'asc'
      end
    end

    context 'when order_direction missing' do
      let(:options) { { order_direction: nil } }

      it 'applies order direction :asc' do
        expect(base.send(:order_direction)).to eq 'asc'
      end
    end
  end

  context 'when skip_order given' do
    let(:options) { { skip_order: true } }

    it 'skips order' do
      expect(sql).not_to include 'ORDER BY'
    end
  end

  context 'when skip_pagination given' do
    let(:options) { { skip_pagination: true, per_page: 2, page: 3 } }

    it 'skips pagination' do
      expect(sql).not_to include 'LIMIT'
      expect(sql).not_to include 'OFFSET'
    end
  end

  describe '::find' do
    let(:current_user) { FakeUser.where(email: 'asd@asd').first_or_create }
    let(:condition) { current_user.id }

    subject do
      Class.new(described_class) {
        def model
          FakeUser
        end
      }.find(condition)
    end

    it { is_expected.to eq current_user }

    context 'when condition is hash' do
      let(:condition) { { email: current_user.email } }

      it { is_expected.to eq current_user }
    end
  end

  context 'when model not overrode' do
    subject { Class.new(described_class).call }

    it { expect { subject }.to raise_exception(NotImplementedError) }
  end
end
