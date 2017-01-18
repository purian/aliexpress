class ProductTypesController < ApplicationController
  before_action :set_product_type, only: [:edit, :update, :show, :destroy, :clear_errors]
  def index
    @product_types = ProductType.paginate(:page => params[:page])
                                .joins(:product)
                                .merge(Product.order(:name))
                                .order(:name)
  end

  def edit
    respond_with @product_type
  end

  def update
    @product_type.update(product_type_params)
    redirect_to product_types_path
  end

  def create
    unless params[:product_type].empty?
      params[:product_type].each do |data|
        product_type = ProductType.find data[:id]
        product_type.option_1 = data[:option_1]
        product_type.option_2 = data[:option_2]
        product_type.option_3 = data[:option_3]
        product_type.aliexpress_link = data[:aliexpress_link]
        product_type.save
      end
    end
    redirect_to product_types_path, notice: "Salvo com sucesso"
  end

  def show
    respond_with @product_type
  end

  def destroy
    @product_type.destroy
    redirect_to product_types_path, alert: "Produto deletado."
  end

  def import_all
    Wordpress.all.each do |wordpress|
      @products = wordpress.get_products
      Product.import(@products, wordpress)
    end
    redirect_to product_types_path, notice: "Produtos importados."
  rescue
    redirect_to product_types_path, alert: "Falha ao importar, checar configurações do Wordpress."
  end

  def product_errors
    @product_types = ProductType.where("product_errors > 0")
                                .paginate(:page => params[:page])
                                .joins(:product)
                                .merge(Product.order(:name))
                                .order(product_errors: :desc)
  end

  def clear_errors
    @product_type.product_errors = 0
    @product_type.save
    redirect_to :back, notice: "Você limpou os erros do produto #{@product_type.product.name}"
  end

  private

  def set_product_type
    @product_type = ProductType.find(params[:id])
  end

  def product_type_params
    params.require(:product_type).permit(:id, :name, :aliexpress_link, :option_1,
                                         :option_2, :option_3, :shipping)
  end
end
