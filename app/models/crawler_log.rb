class CrawlerLog < ActiveRecord::Base
  belongs_to :crawler

  def add_processed(message)
    self.add_message(message)
    self.update(processed: self.processed+=1)
  end

  def add_message(message)
    p message
    self.message.concat("#{message}|")
    case message
    when message.include?("processado com sucesso!")
      self.category_1.concat("#{message}|-------------------|")

    when message.include?("Mais de 5")
      self.category_2.concat("#{message}|-------------------|")

    when message.include?("não disponível na aliexpress!")
      self.category_3.concat("#{message}|-------------------|")

    when message.include?("Link aliexpress não cadastrado")
      self.category_4.concat("#{message}|-------------------|")

    when message.include?("importar do wordpress")
      self.category_5.concat("#{message}|-------------------|")
    end
    self.save!
  end

  # def get_message
  #   self.message.split("|")
  # end
end
