require "watir-webdriver"
class Crawler < ActiveRecord::Base
  belongs_to :aliexpress
  belongs_to :wordpress
  validates :aliexpress_id, :wordpress_id, presence: true
  has_many :crawler_logs

  def run(orders)
    orders_count = orders.nil? ? 0 : orders.count
    @log = CrawlerLog.create!(crawler: self, orders_count: orders_count)
    raise "Não há pedidos a serem executados" if orders.nil? || orders.count == 0

    # @log = CrawlerLog.create!(crawler: self, orders_count: 1)
    @b = Watir::Browser.new :phantomjs
    Watir.default_timeout = 120
    @b.window.maximize
    raise "Falha no login, verifique as informações de configuração aliexpress ou tente novamente mais tarde" unless self.login
    # order = orders
    orders.each do |order|
      @finished = false
      @error = nil
      begin
        tries ||= 3
        @log.add_message("-------------------")
        @log.add_message("Processando pedido ##{order['id']}")
        notes = self.wordpress.get_notes order
        email_enviado = false
        while !email_enviado
          notes.each do |note|
            if note["note"].include? "Pedido(s) na Aliexpress"
              raise "Pedido ja executado!"
            elsif note["note"].include? "FOI APROVADO NA DATA"
              email_enviado = true
            end
          end
          self.send_email order unless email_enviado
        end

        self.empty_cart #Esvazia Carrinho
        customer = order["shipping_address"] #Loop para todos os produtos
        order_items = []
          order["line_items"].each do |item|
            begin
              quantity = item["quantity"]
              raise "Mais de 5 produtos iguais, pulando pedido" if quantity > 5
              product = Product.find_by_name(item["name"])
              raise "Produto #{item["name"]} não encontrado, necessário importar do wordpress" if product.nil?
              if (meta = item["meta"]).empty?
                product_type = ProductType.find_by(product: product)
              else
                name = ""
                item["meta"].each do |option|
                  name.concat("#{option['value']} ")
                end
                product_type = ProductType.find_by(product: product, name: name.strip)
              end
              raise "Produto #{item["name"]} não encontrado, necessário importar do wordpress" if product_type.nil?
              # shipping = product_type.shipping
              # order_items << {product_type: product_type, shipping: shipping}
              order_items << {product_type: product_type}
              raise "Link aliexpress não cadastrado para #{item["name"]}" if product_type.aliexpress_link.nil?
              @b.goto product_type.parsed_link #Abre link do produto
              # frete = @b.div(class: "p-logistics-detail").present? ? @b.div(class: "p-logistics-detail").text : ""
              user_options = [product_type.option_1, product_type.option_2 ,product_type.option_3]
              self.set_options user_options
              #Ações dos produtos
              raise "Erro de estoque, produto #{item["name"]} não disponível na aliexpress!" if !@b.text_field(name: 'quantity').present? #Verifica disponibilidade
              self.add_quantity quantity
              raise "Erro de estoque, produto #{item["name"]} não disponível na aliexpress!" if @b.text_field(name: 'quantity').value.to_i != quantity  #Verifica quantidade
              self.add_to_cart
              @log.add_message("Adicionando #{quantity} #{item["name"]} ao carrinho")
            rescue => e
              @log.add_message(e.message)
              @error = "Erro no produto #{item["name"]}, verificar se o link da aliexpress está correto, este pedido será pulado."
              @log.add_message(@error)
              product_type.add_error if product && product_type
              break
            end
          end
        #Finaliza pedido
        if @error.nil?
          @b.goto 'https://shoppingcart.aliexpress.com/'
          self.fill_shipping_address(customer)
          # self.set_shipping(order_items)
          @b.goto 'https://m.aliexpress.com/shopcart/detail.htm'
          raise "Erro com itens do carrinho, cancelando pedido" if @b.lis(id: "shopcart-").count != order["line_items"].count
          @b.div(class: "buyall").when_present.click #Botão Finalizar pedido
          raise "Erro de cliente: #{@b.lis(class: "item")[3].text} diferente de #{customer["postcode"]}" unless @b.lis(class: "item")[3].text == customer["postcode"]
          @b.button(id: "create-order").when_present.click #Botão Finalizar pedido
          @log.add_message('Finalizando Pedido')
          @finished = true
          order_nos = @b.div(class:"desc_txt").when_present
          # order_nos = self.complete_order(customer)
          raise if !@error.nil?
          @log.add_message("Pedido completado na Aliexpress")
          raise "Erro com numero do pedido vazio" if order_nos.nil?
          self.wordpress.update_order(order, order_nos.text)
          @error = self.wordpress.error
          @log.add_message(@error)
          @log.add_processed("Pedido #{order["id"]} processado com sucesso! Links aliexpress: #{order_nos.text}")
          ProductType.clear_errors(order_items)
        else
          raise
        end
      rescue => e
        # @error = "Erro ao concluir pedido #{order["id"]}, verificar aliexpress e wordpress."
        @log.add_message(e.message)
        @log.add_message(@error)
      rescue Net::ReadTimeout => e
        @log.add_message("Erro de timeout, Tentando mais #{tries-1} vezes")
        retry unless (tries -= 1).zero? || @finished
      end
    end
    @b.close
  rescue => e
    @error = "Erro desconhecido, procurar administrador."
    @log.add_message(e.message)
    @log.add_message(@error)
  end


  #Efetua login no site da Aliexpresss usando user e password
  def login
    tries ||= 3
    @log.add_message("Efetuando login com #{self.aliexpress.email}")
    user = self.aliexpress
    @b.goto "https://login.aliexpress.com/"
    frame = @b.iframe(id: 'alibaba-login-box')
    frame.text_field(name: 'loginId').set user.email
    frame.text_field(name: 'password').set user.password
    frame.button(name: 'submit-btn').click
    frame.wait_while_present
    true
  rescue => e
    @log.add_message(e.message)
    @log.add_message("Erro de login, Tentando mais #{tries} vezes")
    retry unless (tries -= 1).zero?
    false
  end

  #Adiciona item ao carrinho
  def add_to_cart
    sleep 2
    @b.link(id: "j-add-cart-btn").when_present.click
    sleep 2
    if @b.div(class: "ui-add-shopcart-dialog").present?
    else
      @error = "Falha ao adicionar ao carrinho: #{@b.url}"
      @log.add_message(@error)
    end
  end

  #Adiciona quantidade certa do item
  def add_quantity quantity
    (quantity -1).times do
      @b.dl(id: "j-product-quantity-info").i(class: "p-quantity-increase").when_present.click
    end
  end


  #Seleciona o frete
  def set_shipping order_items
    order_items.each do |item|
      product_link = item[:product_type].link_id
      shipping = item[:shipping]
      unless shipping.nil? || shipping == 0
        @b.trs(class: "item-product").each do |product_info|
          if product_info.div(class: "p-title").a.href.include?(product_link)
            product_info.div(class: "product-shipping-select").when_present.click
            sleep 2
            shipping_name = product_info.divs(class: "shipping-line")[shipping-1].text.split("\n")[0]
            @log.add_message("Produto com frete, selecionando frete: #{shipping_name}")
            product_info.radios[shipping-1].when_present.click
            sleep 2
            product_info.button(class: "btn-ok").when_present.click
            sleep 2
          end
        end
      end
    end
  end

  #Selecionar opções do produto na Aliexpress usando array de opções da planilha
  def set_options user_options
    @b.div(id: "j-product-info-sku").dls.each_with_index do |option, index|
      selected = user_options[index]
      if selected.nil?
        option.a.when_present.click
      else
        option.as[selected-1].when_present.click
      end
    end
    sleep 2
  end

  #Iinformações do cliente
  def fill_shipping_address customer
    @b.button(class: "buy-now").when_present.click
    sleep 3
    @b.a(class: "sa-edit").present? ? @b.a(class: "sa-edit").click : @b.a(class: "sa-add-a-new-address").click
    @log.add_message('Adicionando informações do cliente')
    @b.text_field(name: "contactPerson").when_present.set to_english(customer["first_name"]+" "+customer["last_name"])
    sleep 1
    @b.select_list(name: "country").when_present.select "Brazil"
    sleep 1
    address = customer["address_1"]
    address = address + ", "+ customer['number'] if customer['number']
    address = address + " - "+ customer['address_2'] if customer['address_2']
    @b.text_field(name: "address").when_present.set to_english(address)
    sleep 1
    @b.text_field(name: "address2").when_present.set to_english(customer["neighborhood"])
    sleep 1
    arr = self.state.assoc(customer["state"])
    @b.div(class: "sa-province-wrapper").select_list.when_present.select arr[1]
    sleep 1
    @b.text_field(name: "city").when_present.set to_english(customer["city"])
    sleep 1
    @b.text_field(name: "zip").when_present.set customer["postcode"]
    sleep 1
    # @b.text_field(name: "mobileNo").when_present.set ENV['TELEFONE']
    @b.text_field(name: "cpf").when_present.set ENV['CPF']
    sleep 1
    @b.a(class: "sa-confirm").when_present.click
    sleep 3
  end

  #Tabela de conversão de Estados
  def state
    [
      ["AC","Acre"],
      ["AL","Alagoas"],
      ["AP","Amapa"],
      ["AM","Amazonas"],
      ["BA","Bahia"],
      ["CE","Ceara"],
      ["DF","Distrito Federal"],
      ["ES","Espirito Santo"],
      ["GO","Goias"],
      ["MA","Maranhao"],
      ["MT","Mato Grosso"],
      ["MS","Mato Grosso do Sul"],
      ["MG","Minas Gerais"],
      ["PA","Para"],
      ["PB","Paraiba"],
      ["PR","Parana"],
      ["PE","Pernambuco"],
      ["PI","Piaui"],
      ["RJ","Rio de Janeiro"],
      ["RN","Rio Grande do Norte"],
      ["RS","Rio Grande do Sul"],
      ["RO","Rondonia"],
      ["RR","Roraima"],
      ["SC","Santa Catarina"],
      ["SP","Sao Paulo"],
      ["SE","Sergipe"],
      ["TO","Tocantins"],
    ]
  end

  #Retira acentos e caracteres especiais
  def to_english string
    string.tr("ÀÁÂÃÄÅàáâãäåĀāĂăĄąÇçĆćĈĉĊċČčÐðĎďĐđÈÉÊËèéêëĒēĔĕĖėĘęĚěĜĝĞğĠġĢģĤĥĦħÌÍÎÏìíîïĨĩĪīĬĭĮįİıĴĵĶķĸĹĺĻļĽľĿŀŁłÑñŃńŅņŇňŉŊŋÒÓÔÕÖØòóôõöøŌōŎŏŐőŔŕŖŗŘřŚśŜŝŞşŠšſŢţŤťŦŧÙÚÛÜùúûüŨũŪūŬŭŮůŰűŲųŴŵÝýÿŶŷŸŹźŻżŽž", "AAAAAAaaaaaaAaAaAaCcCcCcCcCcDdDdDdEEEEeeeeEeEeEeEeEeGgGgGgGgHhHhIIIIiiiiIiIiIiIiIiJjKkkLlLlLlLlLlNnNnNnNnnNnOOOOOOooooooOoOoOoRrRrRrSsSsSsSssTtTtTtUUUUuuuuUuUuUuUuUuUuWwYyyYyYZzZzZz")
          .tr("^A-Za-z0-9-, ", '')
  end

  #Esvazia carrinho
  def empty_cart
    tries ||= 3
    p 'Esvaziando carrinho'
    @b.goto 'http://shoppingcart.aliexpress.com/shopcart/shopcartDetail.htm'
    empty = @b.link(class: "remove-all-product")
    if empty.present?
      empty.click
      @b.div(class: "ui-window-btn").button.when_present.click
      empty.wait_while_present
    end
  rescue => e
    @log.add_message(e.message)
    @log.add_message("Falha ao esvaziar carrinho, verificar conexão, tentando mais 3 vezes")
    retry unless (tries -= 1).zero?
    exit
  end

  def send_email order
  	date = order["completed_at"].to_date.strftime("%d/%m")
  	name = order["shipping_address"]["first_name"]
  	order_number = order["order_number"]
  	message = "O PEDIDO #{order_number} FOI APROVADO NA DATA #{date} \n #{name},\n Aguarde que em breve seu pedido chegará em sua residência. Dúvidas sobre prazo de envio ou sobre o pedido acesse o campo PERGUNTAS FREQUENTES em nosso site : http://mistermattpulseiras.com.br/perguntas-frequentes/"
    self.wordpress.email_note order, message
  end

end
