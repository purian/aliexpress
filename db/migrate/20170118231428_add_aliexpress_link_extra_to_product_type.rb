class AddAliexpressLinkExtraToProductType < ActiveRecord::Migration
  def change
    add_column :product_types, :aliexpress_link_extra, :string
  end
end
