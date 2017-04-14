# encoding: utf-8
class CrawlerLog < ActiveRecord::Base
  belongs_to :crawler

  def add_processed order, order_nos
    self.add_message("Processado com sucesso! Links aliexpress: #{order_nos}")
    self.category_1.concat("Pedido: <a href='https://mistermattpulseiras.com.br/wp-admin/post.php?post=#{order}&action=edit'>#{order}</a> | Pedido(s) Aliexpress: ")
    order_nos.split(",").each do |order_no|
      self.category_1.concat("| <a href='https://trade.aliexpress.com/order_detail.htm?orderId=#{order_no}'>#{order_no}</a>")
    end
    self.category_1.concat("|-------------------|")
    self.update(processed: self.processed+=1)
  end

  def add_message(message)
    self.message.concat("#{message}|")
    case message
    when /Mais de 5/
      self.category_2.concat("#{message}|-------------------|")

    when /não disponível na aliexpress!/
      self.category_3.concat("#{message}|-------------------|")

    when /Link aliexpress não cadastrado/
      self.category_4.concat("#{message}|-------------------|")

    when /importar do wordpress/
      self.category_5.concat("#{message}|-------------------|")
    end
    self.save!
  end

  # def get_message
  #   self.message.split("|")
  # end
end
