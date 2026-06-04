require 'sequel'

db_url = ENV['DATABASE_URL'] || "postgres://rubymc:RUBYMCJAVA2026@localhost/rubymc"

DB = Sequel.connect(db_url)

DB.create_table?(:users) do
  primary_key :id
  String :discord_id, unique: true, null: false
  String :username
  String :avatar_url
  String :role, default: 'user'
  DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
  DateTime :updated_at
end

DB.create_table?(:payments) do
  String :id, primary_key: true
  foreign_key :user_id, :users, type: Integer
  String :plan_id
  String :plan_label
  BigDecimal :amount, size: [10, 2]
  String :status, default: 'pending'
  String :pix_code, text: true
  String :receipt_path
  String :receipt_ext
  BigDecimal :ocr_amount, size: [10, 2]
  String :ocr_sender
  String :confirmed_by
  DateTime :confirmed_at
  String :rejected_by
  DateTime :rejected_at
  DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
end

DB.create_table?(:active_memberships) do
  primary_key :id
  foreign_key :user_id, :users, type: Integer, unique: true
  String :plan_id
  String :plan_label
  DateTime :expires_at
  TrueClass :role_granted, default: false
  DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
  DateTime :updated_at
end

puts "Migração concluída: tabelas users, payments, active_memberships criadas."
