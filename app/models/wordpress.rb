require 'woocommerce_api'

class Wordpress < ActiveRecord::Base
  validates :name, :url, :consumer_key, :consumer_secret, presence: true
  has_many :crawlers

  @error = nil

  def error
    @error
  end

  def woocommerce
    woocommerce = WooCommerce::API.new(
    self.url, #Url do site
    self.consumer_key, #Consumer Key
    self.consumer_secret, #Consumer Secret
      {
        version: "v2" #Versão da API
      }
    )
    woocommerce
  end

  def get_products
    products = woocommerce.get("products?filter[limit]=1000&fields=id,permalink,title,attributes").parsed_response
    products['products']
  end

  def update_order order, order_nos
    self.update_note order, order_nos
    self.complete_order order
  rescue
    @error = "Erro ao atualizar pedido #{order["id"]} no wordpress, verificar ultimo pedido na aliexpress."
  end

  def email_note order, message
    data = {
      order_note: {
        note: message,
        customer_note: true
      }
    }
    woocommerce.post("orders/#{order["id"]}/notes", data).parsed_response
  end

  def update_note order, order_nos
    #Atualiza pedidos no wordpress com o numero dos pedidos da aliexpress
    data = {
      order_note: {
        note: "Pedido(s) na Aliexpress: #{order_nos}"
      }
    }
    #POST em order notes
    woocommerce.post("orders/#{order["id"]}/notes", data).parsed_response
  end

  def complete_order order
    data = {
      order: {
        status: "on-hold"
      }
    }
    #PUT para mudar a ordem para concluída
    woocommerce.put("orders/#{order["id"]}", data).parsed_response
  end

  def get_orders
    #Pegar todos os pedidos com status Processado, 200, ordem ascendente e apenas dados
    #que serão usados: id,shipping_address,line_items, billing_address
    all_orders = woocommerce.get("orders?filter[limit]=50&filter[order]=asc&status=processing&fields=id,completed_at,shipping_address,billing_address,line_items").parsed_response
    # order = woocommerce.get("orders/5329").parsed_response
    #Converção para array
    all_orders["orders"]
    # order["order"]
  rescue
    @error = "Erro ao importar pedidos do Wordpress, favor verificar configurações."
  end

  def get_notes order
    all_notes = woocommerce.get("orders/#{order["id"]}/notes").parsed_response
    all_notes["order_notes"]
  end
end
