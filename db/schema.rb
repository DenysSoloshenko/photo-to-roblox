# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.0].define(version: 2026_09_14_000100) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "identities", force: :cascade do |t|
    t.integer "user_id", null: false
    t.string "provider", null: false
    t.string "uid", null: false
    t.string "email"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["provider", "uid"], name: "index_identities_on_provider_and_uid", unique: true
    t.index ["user_id"], name: "index_identities_on_user_id"
  end

  create_table "notifications", force: :cascade do |t|
    t.integer "user_id", null: false
    t.integer "order_id", null: false
    t.string "kind", null: false
    t.string "title", null: false
    t.text "body", null: false
    t.datetime "read_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["order_id", "kind"], name: "index_notifications_on_order_id_and_kind", unique: true
    t.index ["order_id"], name: "index_notifications_on_order_id"
    t.index ["user_id", "read_at", "created_at"], name: "index_notifications_for_inbox"
    t.index ["user_id"], name: "index_notifications_on_user_id"
  end

  create_table "orders", force: :cascade do |t|
    t.integer "user_id", null: false
    t.string "public_id", null: false
    t.string "status", default: "payment_pending", null: false
    t.string "payment_status", default: "unpaid", null: false
    t.string "title", null: false
    t.string "scene_type", default: "other", null: false
    t.string "style", default: "roblox_stylized", null: false
    t.text "must_preserve"
    t.text "instructions"
    t.integer "price_cents", default: 1900, null: false
    t.string "currency", default: "USD", null: false
    t.datetime "submitted_at", null: false
    t.datetime "delivery_due_at", null: false
    t.datetime "completed_at"
    t.datetime "purchase_requested_at"
    t.datetime "paid_at"
    t.text "admin_notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "rights_confirmed_at", null: false
    t.jsonb "preview_scene_ir"
    t.string "stripe_checkout_session_id"
    t.string "stripe_payment_intent_id"
    t.datetime "checkout_started_at"
    t.text "stripe_checkout_url"
    t.integer "checkout_attempts", default: 0, null: false
    t.datetime "authorization_expires_at"
    t.datetime "authorized_at"
    t.datetime "capture_requested_at"
    t.datetime "captured_at"
    t.datetime "released_at"
    t.datetime "refund_requested_at"
    t.datetime "refunded_at"
    t.datetime "payment_failed_at"
    t.text "payment_error"
    t.datetime "accepted_at"
    t.datetime "declined_at"
    t.datetime "cancelled_at"
    t.datetime "approved_at"
    t.datetime "generation_started_at"
    t.datetime "generation_finished_at"
    t.integer "generation_attempts", default: 0, null: false
    t.jsonb "generation_metrics", default: {}, null: false
    t.text "generation_error"
    t.index ["payment_status", "created_at"], name: "index_orders_on_payment_status_and_created_at"
    t.index ["public_id"], name: "index_orders_on_public_id", unique: true
    t.index ["status", "delivery_due_at"], name: "index_orders_on_status_and_delivery_due_at"
    t.index ["stripe_checkout_session_id"], name: "index_orders_on_stripe_checkout_session_id", unique: true
    t.index ["stripe_payment_intent_id"], name: "index_orders_on_stripe_payment_intent_id", unique: true
    t.index ["user_id", "created_at"], name: "index_orders_on_user_id_and_created_at"
    t.index ["user_id"], name: "index_orders_on_user_id"
  end

  create_table "stripe_events", force: :cascade do |t|
    t.string "event_id", null: false
    t.string "event_type", null: false
    t.string "order_public_id"
    t.datetime "stripe_created_at"
    t.datetime "processed_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["event_id"], name: "index_stripe_events_on_event_id", unique: true
    t.index ["order_public_id", "processed_at"], name: "index_stripe_events_on_order_public_id_and_processed_at"
  end

  create_table "users", force: :cascade do |t|
    t.string "email", null: false
    t.string "display_name", null: false
    t.string "password_digest"
    t.integer "session_version", default: 0, null: false
    t.datetime "terms_accepted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "password_reset_digest"
    t.datetime "password_reset_sent_at"
    t.index "lower((email)::text)", name: "index_users_on_lower_email", unique: true
    t.index ["password_reset_digest"], name: "index_users_on_password_reset_digest", unique: true
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "identities", "users"
  add_foreign_key "notifications", "orders"
  add_foreign_key "notifications", "users"
  add_foreign_key "orders", "users"
end
