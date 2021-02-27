module Steep
  class SignatureController
    attr_reader :status

    ErrorStatus = Struct.new(:files, :errors, :last_builder, keyword_init: true) do
      def diagnostics
        factory = AST::Types::Factory.new(builder: last_builder)
        errors.map {|error| Diagnostic::Signature.from_rbs_error(error, factory: factory) }
      end
    end
    LoadedStatus = Struct.new(:files, :builder, keyword_init: true)

    FileStatus = Struct.new(:path, :content, :decls, keyword_init: true)

    def initialize(env:)
      builder = RBS::DefinitionBuilder.new(env: env)
      @status = LoadedStatus.new(builder: builder, files: {})
    end

    def self.load_from(loader)
      env = RBS::Environment.from_loader(loader).resolve_type_names
      new(env: env)
    end

    def current_files
      status.files
    end

    def current_env
      current_builder.env
    end

    def current_builder
      case status
      when ErrorStatus
        status.last_builder
      when LoadedStatus
        status.builder
      end
    end

    def apply_changes(files, changes)
      changes.each.with_object({}) do |(path, cs), update|
        old_text = files[path]&.content
        content = cs.inject(old_text || "") {|text, change| change.apply_to(text) }

        buffer = RBS::Buffer.new(name: path, content: content)

        update[path] = begin
                         FileStatus.new(path: path, content: content, decls: RBS::Parser.parse_signature(buffer))
                       rescue RBS::ParsingError => exn
                         FileStatus.new(path: path, content: content, decls: exn)
                       end
      end
    end

    def update(changes)
      updates = apply_changes(current_files, changes)
      paths = Set.new(updates.each_key)
      files = current_files.merge(updates)
      result = update_env(updates, paths: paths)

      @status = case result
                when Array
                  ErrorStatus.new(last_builder: current_builder, errors: result, files: files)
                when RBS::DefinitionBuilder::AncestorBuilder
                  LoadedStatus.new(builder: update_builder(ancestor_builder: result, paths: paths), files: files)
                end
    end

    def update_env(updates, paths:)
      errors = []

      env = current_env.reject do |decl|
        if decl.location
          paths.include?(decl.location.buffer.name)
        end
      end

      updates.each_value do |content|
        if content.decls.is_a?(RBS::ErrorBase)
          errors << content.decls
        else
          begin
            content.decls.each do |decl|
              env << decl
            end
          rescue RBS::LoadingError => exn
            errors << exn
          end
        end
      end

      begin
        env.validate_type_params
      rescue RBS::LoadingError => exn
        errors << exn
      end

      return errors unless errors.empty?

      builder = RBS::DefinitionBuilder::AncestorBuilder.new(env: env.resolve_type_names)
      builder.env.class_decls.each_key do |type_name|
        rescue_rbs_error(errors) { builder.one_instance_ancestors(type_name) }
        rescue_rbs_error(errors) { builder.one_singleton_ancestors(type_name) }
      end
      builder.env.interface_decls.each_key do |type_name|
        rescue_rbs_error(errors) { builder.one_interface_ancestors(type_name) }
      end

      return errors unless errors.empty?

      builder
    end

    def rescue_rbs_error(errors)
      begin
        yield
      rescue RBS::ErrorBase => exn
        errors << exn
      end
    end

    def update_builder(ancestor_builder:, paths:)
      changed_names = Set[]

      old_definition_builder = current_builder
      old_env = old_definition_builder.env
      old_names = type_names(paths: paths, env: old_env)
      old_ancestor_builder = old_definition_builder.ancestor_builder
      old_method_builder = old_definition_builder.method_builder
      old_graph = RBS::AncestorGraph.new(env: old_env, ancestor_builder: old_ancestor_builder)
      add_descendants(graph: old_graph, names: old_names, set: changed_names)
      add_nested_decls(env: old_env, names: old_names, set: changed_names)

      new_env = ancestor_builder.env
      new_ancestor_builder = ancestor_builder
      new_names = type_names(paths: paths, env: new_env)
      new_graph = RBS::AncestorGraph.new(env: new_env, ancestor_builder: new_ancestor_builder)
      add_descendants(graph: new_graph, names: new_names, set: changed_names)
      add_nested_decls(env: new_env, names: new_names, set: changed_names)

      old_definition_builder.update(
        env: new_env,
        ancestor_builder: new_ancestor_builder,
        except: changed_names
      )
    end

    def type_names(paths:, env:)
      env.declarations.each.with_object(Set[]) do |decl, set|
        if decl.location
          if paths.include?(decl.location.buffer.name)
            type_name_from_decl(decl, set: set)
          end
        end
      end
    end

    def type_name_from_decl(decl, set:)
      case decl
      when RBS::AST::Declarations::Class, RBS::AST::Declarations::Module, RBS::AST::Declarations::Interface
        set << decl.name

        decl.members.each do |member|
          if member.is_a?(RBS::AST::Declarations::Base)
            type_name_from_decl(member, set: set)
          end
        end
      end
    end

    def add_descendants(graph:, names:, set:)
      set.merge(names)
      names.each do |name|
        case
        when name.interface?
          graph.each_descendant(RBS::AncestorGraph::InstanceNode.new(type_name: name)) do |node|
            set << node.type_name
          end
        when name.class?
          graph.each_descendant(RBS::AncestorGraph::InstanceNode.new(type_name: name)) do |node|
            set << node.type_name
          end
          graph.each_descendant(RBS::AncestorGraph::SingletonNode.new(type_name: name)) do |node|
            set << node.type_name
          end
        end
      end
    end

    def add_nested_decls(env:, names:, set:)
      tops = names.each.with_object(Set[]) do |name, tops|
        unless name.namespace.empty?
          tops << name.namespace.path[0]
        end
      end

      env.class_decls.each_key do |name|
        unless name.namespace.empty?
          if tops.include?(name.namespace.path[0])
            set << name
          end
        end
      end

      env.interface_decls.each_key do |name|
        unless name.namespace.empty?
          if tops.include?(name.namespace.path[0])
            set << name
          end
        end
      end
    end
  end
end
