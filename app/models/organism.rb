class Organism < ActiveRecord::Base

  linked_to_bioportal :email=>"stuart.owen@manchester.ac.uk"
  
  has_many :assay_organisms
  has_many :models
  has_many :assays,:through=>:assay_organisms  
  has_many :strains, :dependent=>:destroy
  
  has_and_belongs_to_many :projects

  validates_presence_of :title
  
  def can_delete?
    models.empty? && assays.empty?
  end

end
