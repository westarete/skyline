# @private
class Skyline::InlineRef < Skyline::RefObject  

  attr_accessor :previous_referable
  after_save :possibly_destroy_previous_referable
  after_destroy :possibly_destroy_referable

  class << self    
    # Convert an html tag to RefObject tag and update or create RefObject in database
    #
    # ==== Parameters
    # html_node<String>:: the html node from the editor
    # refering_object<Object>:: refering object
    # refering_column_name<Symbol>:: column name in which the data is stored
    # ==== Returns
    # String:: converted html
    # Array:: ids of refs in html
    def parse_html(html_node, refering_object, refering_column_name)    
      old_refs = find_ref_ids_for_object(refering_object, refering_column_name)
            
      h = Hpricot(html_node)
      updated_refs = []
      
      # html tags to be converted to [REF:id]
      iterate_elements = {"a" => {:src => "href", :inner_html => true, :skyline_class => Skyline::LinkRef}, 
                          "img" => {:src => "src", :inner_html => false, :skyline_class => Skyline::ImageRef}                                          
                          } 
      
      iterate_elements.each do |tag, attributes|                
        h.search("#{tag}[@skyline-referable-type]").each do |node|                                 
          ref_obj_id = create_ref_from_node(node, refering_object, refering_column_name, attributes[:src], attributes[:skyline_class])
          if attributes[:inner_html]
            node.swap("[REF:#{ref_obj_id}]#{node.inner_html}[/REF:#{ref_obj_id}]")
          else
            node.swap("[REF:#{ref_obj_id}]")
          end
                  
          updated_refs << ref_obj_id
        end
      end
      
      del = (old_refs - updated_refs)
      unless del.blank?
        self.destroy_all("id IN(#{del.join(',')})") 
        logger.debug("[InlineRef] Destroying refs for #{refering_object.class.name} id: #{refering_object.id} column: #{refering_column_name}. Ref's destroyed: #{del.inspect}")
      end
                  
      [h.to_html, updated_refs]
    end            
    
    # Create hash of InlineRef objects for specified object and column name
    #
    # ==== Paramenters
    # object<Object>:: the object containing the Inline Refs
    # column_name<String>:: column name in which the inline refs are stored as [REF:id] tags
    #
    # ==== Retruns
    # Hash:: a hash of inlinerefs with id as key and object as value
    def hash_refs_for_object(object, column_name)
      types = [Skyline::ImageRef,Skyline::LinkRef].map(&:name)
      refs = Skyline::RefObject.all(:conditions => {:refering_id => object.id, :refering_type => object.class.name, :refering_column_name => column_name.to_s, :type => types})
      refs.inject({}){|mem,o| mem[o.id] = o; mem }
    end
    
    # Convert [REF:id] tags to html tags
    #
    # ==== Parameters
    # object<Object>:: the object containing the string to be converted
    # column_name<String>:: name of column containing the string to be converted
    # with_refs<Boolean>:: boolean that sets wether to print skyline-reference tags into the html tag
    # 
    # ==== Returns
    # String:: converted html text
    def convert(object,column_name,with_refs=false,options={})
      options.reverse_merge! :nullify => false
      
      refs = self.hash_refs_for_object(object, column_name)
      value = object[column_name]
      
      return value unless value.kind_of?(String)
      v = value.gsub(/\[REF:(\d+)\]/) do |match|
        i = match[5..-2]
        if refs[i.to_i]
          refs[i.to_i].to_start_html(with_refs,options)
        else
          ""
        end
      end
    
      outp = v.gsub(/\[\/REF:(\d+)\]/) do |match|
        i = match[6..-2]
        if refs[i.to_i]
          refs[i.to_i].to_end_html
        else
          ""
        end
      end
    end
    
    private
    # find ref idss by sql for refering object
    # ==== Parameters
    # refering_object<Object>:: Object containing the refs
    # refering_column_name<Symbol>:: column name where refs are stored
    #
    # ==== Returns
    # Array:: Array of ids of refering objects
    def find_ref_ids_for_object(refering_object, refering_column_name)            
      # Skyline::InlineRef.connection.select_values("SELECT id FROM #{self.table_name} WHERE refering_id = '#{refering_object.id}' AND refering_type = '#{refering_object.class.name}' AND refering_column_name = '#{refering_column_name.to_s}'").map(&:to_i)
      Skyline::InlineRef.find(
        :all, 
        :conditions => {
          :refering_id => refering_object.id, 
          :refering_type => refering_object.class.name, 
          :refering_column_name => refering_column_name.to_s
        }
      ).collect(&:id)
    end
    
    # create ref_object from html node
    #
    # ==== Parameters
    # html_node<String>:: html node to be converted to ref_object
    # refering_object<Object>:: object containing the html node
    # refering_column_name<Symbol>:: column name of the object containing the html node
    # src_attr<String>:: attribute of the html node containing the source of the element
    # skyline_class<Class>:: sti class for the ref_object
    #
    # ==== Returns
    # Integer:: id of the new ref_object
    def create_ref_from_node(html_node, refering_object, refering_column_name, src_attr, skyline_class)            
      id, ref_id, ref_type = remove_attributes(html_node, ["skyline-ref-id", "skyline-referable-id", "skyline-referable-type"])
      
      referable_params = {}
      referable_params[:uri] = html_node[:href]

      options = []        
      html_node.remove_attribute(src_attr)
      
      options = html_node.attributes.to_hash.inject({}) do |result, element|
        result[element.first.to_s] = element.last.to_s
        result
      end
   
      new_ref = skyline_class.find_by_id_and_refering_type_and_refering_id_and_refering_column_name(id,refering_object.class.name,refering_object.id,refering_column_name.to_s) unless id.blank?
      logger.warn "--> new_ref.id : #{new_ref && new_ref.id}"
      new_ref ||= skyline_class.new

      new_ref.previous_referable = new_ref.referable.dup if new_ref.referable
        
      new_ref.attributes = {
        :referable_id => ref_id,
        :referable_type => ref_type,
        :options => options, 
        :refering_id => refering_object.id, 
        :refering_type => refering_object.class.name,
        :refering_column_name => refering_column_name.to_s
      }
      
      new_ref.referable.reload if new_ref.referable
      if ref_type == "Skyline::ReferableUri"
        new_ref.referable ||= ref_type.constantize.new

        if referable_params.kind_of?(Hash)
          referable_params.each do |k, v|
            new_ref.referable.send(k.to_s + "=", v) if new_ref.referable.respond_to?(k.to_s + "=")
          end
        end
      end

      new_ref.save!
      
      new_ref.id
    end
    
    # Remove multiple attributes from html_node
    # ==== Parameters
    # node<String>:: html node
    # attributes<Array>:: attributes to be stripped
    # ==== Returns
    # Array:: values of removed attributes
    def remove_attributes(node, attributes)
      ret = attributes.inject([]) do |result, element|
        result << node.remove_attribute(element).to_s.strip
        result
      end
    end
  end    
  
  protected
  def possibly_destroy_previous_referable
    return unless self.previous_referable
    if previous_referable != self.referable
      previous_referable.destroy if previous_referable.kind_of?(Skyline::ReferableUri)
    end
  end

  def possibly_destroy_referable
    self.referable.destroy if self.referable.kind_of?(Skyline::ReferableUri)
  end  
end
