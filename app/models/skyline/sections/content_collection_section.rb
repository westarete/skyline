# @private
class Skyline::Sections::ContentCollectionSection < ActiveRecord::Base
  include Skyline::Sections::Interface
  include Skyline::Taggable
  taggable_scope lambda{|ccs| ccs.content_type}
  
  validates_presence_of :content_type
  validates_numericality_of :number, :greater_than => 0
  
  def content_class
    @content_class ||= self.content_type.constantize    
  end
  
  def content_name
    if self.content_class.name.demodulize == "Data" 
      self.content_class.parent.name.underscore 
    else
      self.content_class.name.underscore 
    end    
  end
  
  def collection_name
    self.content_name.pluralize.to_sym
  end
  
  def collection
    self.full_collection.scoped(:limit => self.number)
  end
  
  def full_collection
    self.content_class.published.with_tags(self.tags).scoped(:limit => self.number)
  end
  
  def clone
    returning super do |clone|
      clone.associated_tags = self.associated_tags.collect{|associated_tag| associated_tag.clone}
    end
  end  
end
