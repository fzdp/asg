module Asg
  class Structure
    Commit = Struct.new(:tree, :parents, :message)
    Reference = Struct.new(:value, :is_linked)
  end
end
