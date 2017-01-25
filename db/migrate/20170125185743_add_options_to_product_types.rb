class AddOptionsToProductTypes < ActiveRecord::Migration
  def change
    add_column :product_types, :option_1_extra, :integer
    add_column :product_types, :option_2_extra, :integer
    add_column :product_types, :option_3_extra, :integer
  end
end
