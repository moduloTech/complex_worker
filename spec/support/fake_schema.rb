# frozen_string_literal: true

ActiveRecord::Schema.define(version: 1) do
  create_table :fake_users, force: :cascade do |t|
    t.string :first_name
    t.string :last_name
    t.string :email
    t.timestamps
  end
end
