# frozen_string_literal: true

require 'modulorails/basic_worker'
require 'action_controller/metal/strong_parameters'

# Author: varaby_m@modulotech.fr
RSpec.describe Modulorails::BasicWorker do
  describe '#initialize' do
    it 'raises' do
      expect { subject }.to(
        raise_exception(NotImplementedError, 'Never use this class directly. Inherit!')
      )
    end
  end

  describe 'after initialize callback' do
    subject do
      Class.new(described_class) {
        attr_reader :a

        set_callback :initialize, :after, -> { @a = 1 }

        def call
          self
        end
      }.call
    end

    it 'executes callback' do
      expect(subject.a).to eq 1
    end
  end

  describe '::require_attributes' do
    let(:optkeys) { %i[a b c d] }
    let(:options) do
      optkeys.map.with_index(1) { |k, i| [k, i] }.to_h
    end
    let(:base_class) do
      Class.new(described_class) do
        attr_reader :a, :b, :c, :d

        require_attributes :a, :b
        require_attributes :c, :d, optional: true

        def call
          self
        end
      end
    end

    subject { base_class.call(options) }

    it 'inits required and optional attributes' do
      expect(subject).to respond_to :a, :b, :c, :d
      expect(subject.a).to eq 1
      expect(subject.b).to eq 2
      expect(subject.c).to eq 3
      expect(subject.d).to eq 4
    end

    context 'when required_attribute nil' do
      let(:options) do
        { a: nil, b: nil }
      end

      it 'not raises' do
        expect { subject }.not_to raise_exception
        expect(subject.a).to be_nil
        expect(subject.b).to be_nil
      end
    end

    context 'when required_attribute missing' do
      let(:optkeys) { %i[a] }

      it 'raises' do
        expect { subject }.to raise_exception(KeyError, 'key not found: :b')
      end
    end

    context 'when optional_attribute missing' do
      let(:optkeys) { %i[a b d] }

      it 'not raises' do
        expect { subject }.not_to raise_exception
        expect(subject).to respond_to :a, :b, :c, :d
        expect(subject.c).to be_nil
      end
    end

    context 'when child class adds new attributes' do
      let(:optkeys) { %i[a b c d x y] }

      let(:nested_class) do
        Class.new(base_class) {
          attr_reader :x, :y

          require_attributes :x
          require_attributes :y, optional: true
        }
      end

      subject { nested_class.call(options) }

      it { is_expected.to respond_to(*optkeys) }

      it 'initializes both parent and child attributes' do
        expect(subject.x).to eq 5
        expect(subject.y).to eq 6
      end

      context 'when some attributes are skipped' do
        let(:optkeys) { %i[b c d] }

        subject do
          Class.new(nested_class) do
            skip_attributes :x, :y, :a
          end.call(options)
        end

        it 'not raises' do
          expect { subject }.not_to raise_exception
        end

        it 'initializes other attributes' do
          expect(subject.a).to be_nil
          expect(subject.x).to be_nil
          expect(subject.y).to be_nil
          expect(subject.b).to eq 1
          expect(subject.c).to eq 2
          expect(subject.d).to eq 3
        end
      end
    end
  end

  describe '::call' do
    subject do
      Class.new(described_class) {
        attr_reader :a

        set_callback :initialize, :after, -> { @a = 2 }

        def call
          @a = 1
          self
        end
      }.call
    end

    it 'initializes and executes #call' do
      expect(subject.a).to eq 1
    end
  end

  describe '#call' do
    subject { Class.new(described_class).call }

    it 'raises' do
      expect { subject }.to raise_exception(NotImplementedError, 'Override #call method')
    end

    context 'when overrode' do
      subject do
        Class.new(described_class) {
          def call
          end
        }.call
      end

      it 'not raises' do
        expect { subject }.not_to raise_exception
      end
    end
  end

  describe '::call_self' do
    let(:klass) do
      Class.new(described_class) {
        attr_reader :a

        set_callback :initialize, :after, -> { @a = 2 }

        def call
          @a = 1
          3
        end
      }
    end

    subject { klass.call_self }

    it 'initializes and executes #call' do
      expect(subject.a).to eq 1
    end

    it 'returns self' do
      expect(subject).to be_an_instance_of klass
    end

    it 'writes #call result to #result' do
      expect(subject.result).to eq 3
    end

    context 'when :result attribute is required' do
      subject do
        Class.new(described_class) {
          require_attributes :result, optional: true

          def call
          end
        }.call
      end

      it 'raises' do
        expect { subject }.to raise_exception(ArgumentError, ':result attribute is reserved')
      end
    end
  end

  describe '#permit_attributes' do
    let(:params_hash) do
      { a: 1, b: 2, c: 3 }
    end
    let(:params) do
      ActionController::Parameters.new(params_hash)
    end

    subject do
      Class.new(described_class) {
        require_attributes :params

        def call
          permit_attributes(params, :a, :b)
        end
      }.call(params: params)
    end

    it 'permits attributes' do
      expect(subject.key?(:a)).to be true
      expect(subject.key?(:b)).to be true
    end

    it 'reject not permitted attributes' do
      expect(subject.key?(:c)).to be false
    end

    context 'when params is Hash' do
      let(:params) do
        { a: 1, b: 2, c: 3 }
      end

      it 'is not filtered' do
        expect(subject.key?(:c)).to be true
      end
    end

    context 'when params is not a hash nor responds to :permit' do
      let(:params) { 1 }

      it 'replaces params with empty hash' do
        is_expected.to be_empty
        is_expected.to eq({})
      end
    end
  end

  describe '#errors' do
    let(:klass) do
      Class.new(described_class) {
        require_attributes :set_result, :set_error

        def call
          @errors = set_error
          set_result
        end
      }
    end

    let(:set_error) { %i[a b] }
    let(:ar_errors) { [] }
    let(:set_result) { nil }

    subject { klass.call_self(set_result: set_result, set_error: set_error).errors }

    it { is_expected.to eq set_error }

    context 'when result is activemodel' do
      let(:set_result) { FakeUser.new.tap { |u| ar_errors.each { |e| u.errors.add(:base, e) } } }

      it { is_expected.to be_empty }

      context 'when ar has errors' do
        let(:ar_errors) { ['cc'] }

        it { is_expected.to eq ar_errors }
      end
    end
  end

  describe '#success?' do
    let(:klass) do
      Class.new(described_class) {
        require_attributes :set_error

        def call
          @errors = set_error
        end
      }
    end

    let(:set_error) { nil }

    subject { klass.call_self(set_error: set_error).success? }

    it { is_expected.to be true }

    context 'when any errors present' do
      let(:set_error) { 1 }

      it { is_expected.to be false }
    end
  end
end
