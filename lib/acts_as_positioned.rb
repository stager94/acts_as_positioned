module ActsAsPositioned

  def self.included(base)
    base.extend(ClassMethods)
  end

  module ClassMethods
    attr_accessor :params

    def by_scope
      params[:by_scope].present? && "#{self.name}.#{params[:by_scope].to_s}" || nil
    end

    def by_method
      params[:by_method].present? && "self.#{params[:by_method].to_s}" || nil
    end

    def by_field
      params[:by_field].present? && "#{self.name}.where(#{params[:by_field]}: self.#{params[:by_field]})" || nil
    end

    def under
      params[:under].present? && "self.#{params[:under].to_s}.#{self.name.tableize}" || nil
    end

    def default
      self.name
    end

    def acts_as_positioned(opts={})
      self.params = opts
      positioned_under = by_field || by_method || by_scope || under || default
      
      class_eval <<-CGF
        include ActsAsPositioned::InstanceMethods
        def siblings_in_position
          #{positioned_under || []}
        end

        attr_accessor :old_position
        attr_accessor :should_fix_positions
        before_save :set_old_position
        after_save :fix_positions
        after_destroy :fix_positions
      CGF
    end

  end

  module InstanceMethods
    
    def set_old_position
      if self.position_changed? || self.position.blank? || self.position == 0
        self.should_fix_positions = true
        begin
          count = siblings_in_position.count + 1
          self.old_position = self.new_record? ? count : self.class.find(self.id).position
          self.position = count if self.position.blank? || self.position == 0
        rescue
          #fail gracefully
        end
      else
        self.should_fix_positions = false
        return true
      end 
    end

    def fix_positions
      begin
        return true unless self.should_fix_positions
        if !self.old_position.nil? && self.old_position >= self.position 
          broken_records = siblings_in_position.reorder("position ASC, updated_at DESC")
        else
          broken_records = siblings_in_position.reorder("position ASC, updated_at ASC")
        end

        broken_records.each_with_index do |s,i|
          s.update_column :position, i+1
        end
      rescue
        #fail gracefully
      end
    end
  end

end

ActiveRecord::Base.send :include, ActsAsPositioned