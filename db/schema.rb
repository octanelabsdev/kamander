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

ActiveRecord::Schema[8.1].define(version: 2026_07_03_073049) do
  create_table "app_destinations", force: :cascade do |t|
    t.json "accessory_names", default: [], null: false
    t.string "config_file", null: false
    t.datetime "created_at", null: false
    t.integer "managed_app_id", null: false
    t.string "name"
    t.string "proxy_host"
    t.json "servers", default: {}, null: false
    t.string "service_name", null: false
    t.string "ssh_user"
    t.datetime "updated_at", null: false
    t.index ["managed_app_id", "config_file"], name: "index_app_destinations_on_managed_app_id_and_config_file", unique: true
    t.index ["managed_app_id", "name"], name: "index_app_destinations_on_managed_app_id_and_name"
    t.index ["managed_app_id"], name: "index_app_destinations_on_managed_app_id"
  end

  create_table "destination_statuses", force: :cascade do |t|
    t.integer "app_destination_id", null: false
    t.datetime "checked_at"
    t.json "containers", default: [], null: false
    t.datetime "created_at", null: false
    t.string "error"
    t.integer "state", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["app_destination_id"], name: "index_destination_statuses_on_app_destination_id", unique: true
  end

  create_table "managed_apps", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "discovered_at", null: false
    t.string "display_name"
    t.datetime "last_scanned_at", null: false
    t.integer "position", default: 0, null: false
    t.string "proxy_host"
    t.string "repo_path", null: false
    t.string "service_name", null: false
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["repo_path"], name: "index_managed_apps_on_repo_path", unique: true
    t.index ["status", "position"], name: "index_managed_apps_on_status_and_position"
  end

  create_table "settings", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "default_ssh_user", default: "deploy", null: false
    t.string "scan_root", default: "~/Development", null: false
    t.datetime "updated_at", null: false
  end

  add_foreign_key "app_destinations", "managed_apps"
  add_foreign_key "destination_statuses", "app_destinations"
end
