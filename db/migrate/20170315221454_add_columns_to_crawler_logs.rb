class AddColumnsToCrawlerLogs < ActiveRecord::Migration
  def change
    add_column :crawler_logs, :category_1, :string, default: ""
    add_column :crawler_logs, :category_2, :string, default: ""
    add_column :crawler_logs, :category_3, :string, default: ""
    add_column :crawler_logs, :category_4, :string, default: ""
    add_column :crawler_logs, :category_5, :string, default: ""
  end
end
