module User
  class Module < BaseDsl
    # Эти accessor-ы не нужны и не используются. А методы modules и methods вообще перекрываются ниже.
    attr_accessor :name, :body, :modules, :new_object, :attrs, :methods

    # @param updating [boolean] выполняется Module.update
    def initialize name, new_object, updating = false
      super name, new_object

      @external = false
      if @new_object
        if !updating && $space.moduleAccount.modules.has_key?(@name)
          raise "Модуль #{@name} уже существует. Выполнение операции <create> с указанным именем невозможно"
        end
        @modules = Array.new
        @attrs = Hash.new
        @methods = Hash.new
        @state_mashines = []
      else
        if !$space.moduleAccount.modules.has_key?(@name)
          raise "Модуля #{@name} не существует. Выполнение операции <modify> невозможно"
        end
        @dh_inserted[:attrs]=[]
        @dh_inserted[:def_values]=[]
        @dh_inserted[:methods]=[]
        @dh_inserted[:modules]=[]
        @dh_inserted[:state_mashines]=[]
        @dh_inserted[:descr]=''
        @dh_inserted[:actions_on_change]=[]

        @dh_removed[:attrs]=[]
        @dh_removed[:methods]=[]
        @dh_removed[:modules]=[]
        @dh_removed[:state_mashines]=[]
        @dh_removed[:descr]=''
        @dh_removed[:actions_on_change]=[]

        #Получить все данные по старому модулю
        module_def = $space.moduleAccount.module_defs[@name]
        @descr = module_def[0]
        dh = module_def[1]
        @attrs = Marshal.load(Marshal.dump(dh[:attrs])) || Hash.new
        @methods = Marshal.load(Marshal.dump(dh[:methods])) || Hash.new
        @modules = Marshal.load(Marshal.dump(dh[:modules])) || []
        @state_mashines = Marshal.load(Marshal.dump(dh[:state_mashines])) || []
        @geo_sign = dh[:geo_sign]
        @subsystems = Marshal.load(Marshal.dump(module_def[2])) || []
      end
    end

    def self.recreate name, &block
      delete name rescue nil
      create name, &block
    end

    def self.create name, &block
      raise 'Ошибка формата команды. Пропущен блок do ... end или { ... }' unless block_given?
      raise 'Неверный формат параметра команды <create>. Имя модуля имеет тип Symbol :TestOfTheTest' unless name.class == Symbol
      const = User.module_eval name.to_s rescue nil
      raise "Ошибка именования модуля. В системе существует модуль или класс с именем #{name}" if const
      user_module = Module.new name, true
      user_module.instance_eval &block
      user_module.insert
    end

    def self.modify name, &block
      raise 'Ошибка формата команды. Пропущен блок do ... end или { ... }' if block == nil
      raise 'Неверный формат параметра команды <modify>. Имя модуля имеет тип Symbol :TestOfTheTest' if name.class != Symbol
      user_module=Module.new(name, false)
      user_module.instance_eval(&block)
      user_module.update
    end

    # Аналог recreate, но без пересоздания модуля
    def self.update name, &block
      # Если модуля нет, то просто выполняем Module.create
      return create name, &block unless get(name)
      raise 'Ошибка формата команды. Пропущен блок do ... end или { ... }' unless block
      raise 'Неверный формат параметра команды <update>. Имя модуля имеет тип Symbol :TestOfTheTest' if name.class != Symbol
      new_module = Module.new name, true, true
      new_module.instance_eval(&block)
      old_module = Module.new name, false
      changed = old_module.merge! new_module
      old_module.update if changed
    end

    def insert
      if @new_object == true
        dh = Hash.new
        dh[:attrs] = @attrs
        dh[:modules] = @modules
        dh[:methods] = @methods
        dh[:state_mashines] = @state_mashines
        dh[:geo_sign] = @geo_sign
        $space.moduleAccount._insert(@name, @descr, dh, @subsystems)
      end
    end

    def update
      if @new_object == false
        dh = Hash.new
        dh[:attrs] = @attrs
        dh[:modules] = @modules
        dh[:methods] = @methods
        dh[:state_mashines] = @state_mashines
        dh[:geo_sign] = @geo_sign
        $space.moduleAccount._update(@name, @descr, dh, @subsystems, @dh_classified, @external)
      end
    end

    def do_not_notify
      @external = true
    end

    def add_state_mashines *sms
      sms.each { |sm| add_state_mashine sm }
    end
    alias add_state_machines add_state_mashines

    def state_mashines *sms
      raise "Команда state_mashines доступна только при создании нового модуля командой create. \nНеобходимо использовать команду add_state_mashines" unless @new_object
      sms.each { |sm| add_state_mashine sm }
    end
    alias state_machines state_mashines

    def add_state_mashine sm
      mod_name = 'SM_' + sm.to_s
      raise "Модуль StateMashine #{sm.to_s} не был построен" if !$space.moduleAccount.modules.has_key?(mod_name.intern)
      raise "Класс #{@name.id2name} уже содержит машину состояний #{sm.to_s}" if @state_mashines.find { |el| el == sm }
      @state_mashines << sm
      @dh_inserted[:state_mashines] << sm  unless @new_object
    end
    alias add_state_machine add_state_mashine

    def remove_state_mashines *sms
      raise 'Команда <remove_state_machines> доступна только при модификации существующего модуля командой <modify>.' if @new_object
      if sms
        sms.each do |sm|
          if @state_mashines.find { |el| el == sm }
            @state_mashines.delete(sm)
            @dh_removed[:state_mashines] << sm
          else
            raise "Модуль #{@name.id2name} не содержит машины состояний #{sm.to_s}"
          end
        end
      end
    end
    alias remove_state_machines remove_state_mashines

    def modules *names
      raise "Команда <modules> доступна только при создании нового модуля командой <create>. \nНеобходимо использовать команду <add_modules>" if !@new_object
      names.each do |name|
        @modules.push name
      end
    end

    def add_modules *names
      raise "Команда <add_modules> доступна только при модификации существующего модуля командой <modify>. \nНеобходимо использовать команду <modules>" if @new_object
      ex_arr = []
      names.each do |name|
        if @modules.find { |el| el == name }
          ex_arr << name.id2name
        else
          @modules.push name
          @dh_inserted[:modules] << name
        end
      end
      if ex_arr.size > 0
        raise "Модуль #{@name.id2name} уже содержит модуль #{ex_arr.join(', ')}"
      end
    end

    def remove_modules *names
      raise 'Команда <remove_modules> доступна только при модификации существующего модуля командой <modify>.' if @new_object
      ex_arr = []
      names.each do |name|
        if @modules.find { |el| el == name }
          @dh_removed[:modules] << name
          @modules.delete(name)
        else
          ex_arr << name.id2name
        end
      end
      if ex_arr.size > 0
        raise "Модуль #{@name} не содержит модуль #{ex_arr.join(', ')}"
      end
    end

    def attributes attrs
      raise "Команда <attributes> доступна только при создании нового модуля командой <create>. \nНеобходимо использовать команду <add_attributes>" if !@new_object
      if attrs
        attrs.each_pair do |attr, value|
          mattr = ModuleAttribute.new(attr, value)
          @attrs[attr]=mattr
        end
      end
    end

    alias атрибуты attributes

    def attribute sym_name, &block
      raise "Команда <attribute> доступна только при создании нового модуля командой <create>. \nНеобходимо использовать команду <add_attribute>" if !@new_object
      attribute = ModuleAttribute.new sym_name, nil
      attribute.instance_eval &block if block_given?
      @attrs[sym_name] = attribute
    end

    alias атрибут attribute

    def add_attribute attr, &block
      raise "Команда <add_attribute> доступна только при модификации существующего модуля командой <modify>. \nНеобходимо использовать команду <attribute>" if @new_object
      if @attrs.has_key?(attr)
        raise "Модуль #{@name.id2name} уже содержит аттрибут #{attr.to_s}"
      else
        raise "Атрибут #{StringUtil.wrap attr} модуля #{StringUtil.wrap @name} одновременно добавляется и удаляется внутри одного modify" if @dh_removed[:attrs].include?(attr)
        mattr = ModuleAttribute.new(attr, nil)
        mattr.instance_eval(&block) if block_given?
        @attrs[attr]=mattr
        @dh_inserted[:attrs] << attr #.id2name
      end
    end

    def add_attr_instance attr_instance
      raise "Команда <add_attribute> доступна только при модификации существующего модуля командой <modify>. \nНеобходимо использовать команду <attribute>" if @new_object
      if @attrs.has_key?(attr_instance.attr_name)
        raise "Модуль #{@name.id2name} уже содержит аттрибут #{attr.to_s}"
      else
        raise "Атрибут #{StringUtil.wrap attr_instance.attr_name} модуля #{StringUtil.wrap @name} одновременно добавляется и удаляется внутри одного modify" if @dh_removed[:attrs].include?(attr_instance.attr_name)
        @attrs[attr_instance.attr_name]=attr_instance
        @dh_inserted[:attrs] << attr_instance.attr_name #.id2name
      end
    end
    def add_attributes attrs
      raise "Команда <add_attributes> доступна только при модификации существующего модуля командой <modify>. \nНеобходимо использовать команду <attributes>" if @new_object
      if attrs
        ex_arr = []
        attrs.each_pair do |attr, value|
          if @attrs.has_key?(attr)
            ex_arr << attr
          else
            raise "Атрибут #{StringUtil.wrap attr} модуля #{StringUtil.wrap @name} одновременно добавляется и удаляется внутри одного modify" if @dh_removed[:attrs].include?(attr)
            @dh_inserted[:attrs] << attr #.id2name
            mattr = ModuleAttribute.new(attr, value)
            @attrs[attr]=mattr
          end
        end
        if ex_arr.size > 0
          raise "Модуль #{@name.id2name} уже содержит аттрибут(ы) #{ex_arr.join(',')}"
        end
      end
    end

    def change_default_value attrs
      raise 'Команда <change_default_value> доступна только при модификации существующего модуля командой <modify>' if @new_object
      if attrs
        ex_arr = []
        attrs.each_pair do |attr, value|
          raise 'Параметр(ы) команды <change_default_value> должен быть типа Symbol.' if attr.class != Symbol
          if !@attrs.has_key?(attr)
            ex_arr << attr
          else
            if @attrs[attr].def_value != value
              @dh_inserted[:def_values] << attr
              @attrs[attr].def_value = value
            end
          end
        end
        if ex_arr.size > 0
          raise "Ошибка в команде <change_default_value>. Модуль #{@name.id2name} не содержит аттрибут(ы) #{ex_arr.join(', ')}"
        end
      end
    end

    def change_options attr_name, opt_hash
      raise 'Команда <change_option> доступна только при модификации существующего модуля командой <modify>' if @new_object
      raise 'Имя атрибута должно быть типа Symbol' if attr_name.class != Symbol
      raise 'Опции атрибута должны задаваться в виде :opt1 => значение1, :opt2 => значение2, ...' unless opt_hash.class == Hash
      attr = @attrs[attr_name]
      raise "Ошибка в команде <change_option>. Модуль #{@name} не содержит аттрибут #{attr_name}" unless attr
      old_options = attr.get_options || Hash.new
      opts = old_options.merge! opt_hash
      opts.delete_if { |option_name, option_value| option_value.nil? }
      attr.options opts
      @dh_inserted[:attr_options] ||= []
      @dh_inserted[:attr_options] << attr_name unless @dh_inserted[:attr_options].include?(attr_name)
    end
    def move_attribute attr, &block
      move_attributes attr, &block
    end
    def move_attributes *attrs, &block
      raise "Команда <move_attributes> доступна только при модификации существующего модуля командой <modify>." if @new_object
      if attrs
        attrs.each{|attr|
          raise "Модуль #{@name.id2name} не содержит аттрибут #{attr.to_s}" unless @attrs.has_key?(attr)
        }
      end
      move_to_module = MoveToModule.new
      move_to_module.instance_eval(&block) if block_given?
      #Найти модуль, куда переносится атрибут
      raise "Не найден модуль #{move_to_module.module_name}" unless $space.moduleAccount.modules[move_to_module.get_module_name.to_sym]
      #Добавим атрибуты в target модуль
      target_module = Module.new(move_to_module.get_module_name, false)
      attrs.each{|attr|
        move_attribute = Marshal.load(Marshal.dump(@attrs[attr]))
        target_module.add_attr_instance move_attribute
      }
      target_module.update
      #Удалим из текущего модуля
      attrs.each{|attr|
        remove_attribute attr
      }
    end

    def remove_attributes *attrs
      raise 'Команда <remove_attributes> доступна только при модификации существующего модуля командой <modify>.' if @new_object
      if attrs
        ex_arr = []
        attrs.each do |attr|
          if attr.class == Symbol || attr.class == String then
            if @attrs.has_key?(attr)
              raise "Атрибут #{StringUtil.wrap attr} модуля #{StringUtil.wrap @name} одновременно добавляется и удаляется внутри одного modify" if @dh_inserted[:attrs].include?(attr)
              @dh_removed[:attrs] << attr #.id2name
              @attrs.delete(attr)
            else
              ex_arr << attr
            end
          else
            raise 'Параметр(ы) команды <remove_attributes> должен быть типа Symbol или типа String.'
          end
        end
        if ex_arr.size > 0
          raise "Модуль #{@name.id2name} не содержит аттрибут(ы) #{ex_arr.join(',')}"
        end
      end
    end

    def remove_attribute attr
      raise 'Команда <remove_attribute> доступна только при модификации существующего модуля командой <modify>.' if @new_object
      if attr.class == Symbol || attr.class == String then
        remove_attributes attr
      else
        raise 'Параметр команды <remove_attribute> должен быть типа Symbol или типа String.'
      end
    end

    def register_method_def name, src
      name = name.to_sym
      unless @new_object
        raise "Метод #{StringUtil.wrap name} модуля #{StringUtil.wrap @name} одновременно добавляется и удаляется внутри одного modify" if @dh_removed[:methods].include?(name.to_s)
        @dh_inserted[:methods] << name.id2name
      end
      @methods[name] = src
    end

    def methods(definitions=nil, &block)

      if block_given?
        dsl_parser = Thread.current[:dsl_parser]
        raise "no dsl parser found for current thread #{Thread.current}" unless dsl_parser
        begin
          m = dsl_parser.define_dsl_module &block
          m.each_dsl_method do |name, src, type|
            case type
              when :defs
                register_method_def('_self_'+name, src)
              else
                register_method_def(name, src)
            end
          end
        rescue Exception => err
          $log.error "Parse error= #{err} #{dsl_parser.root_node}!"
          raise err
        end
      else
        raise 'В команде <methods> должны быть указаны методы в формате :meth1 => %{def meth1 ... end},:meth2=>...' unless definitions.respond_to? :each_pair
        definitions.each_pair do |name, definition|
          register_method_def(name, definition)
        end
      end
    end

    alias методы methods

    def add_methods definitions
      methods definitions
    end

    def remove_method meth
      raise 'Команда <remove_method> доступна только при модификации существующего модуля командой <modify>.' if @new_object
      raise 'Параметр команды <remove_method> должен быть типа Symbol.' if meth.class != Symbol
      remove_methods meth
    end

    def remove_methods *meths
      raise 'Команда <remove_methods> доступна только при модификации существующего модуля командой <modify>.' if @new_object
      if meths
        ex_arr = []
        meths.each do |meth|
          raise 'Параметр команды <remove_methods> должен быть типа Symbol.' if meth.class != Symbol
          if @methods.has_key?(meth)
            raise "Метод #{StringUtil.wrap meth} модуля #{StringUtil.wrap @name} одновременно добавляется и удаляется внутри одного modify" if @dh_inserted[:methods].include?(meth.to_s)
            @dh_removed[:methods] << meth.id2name
            @methods.delete(meth)
          else
            ex_arr << meth.id2name
          end
        end
        if ex_arr.size > 0
          raise "Модуль #{@name.id2name} не содержит метод(ы) #{ex_arr.join(', ')}"
        end
      end
    end

    def add_action_on_change attr_actions
      raise 'Команда <add_action_on_change> доступна только при модификации существующего модуля командой <modify>.' if @new_object
      raise 'В команде <add_action_on_change> должны быть указаны параметры: имя атрибута и действие' if attr_actions == nil
      ex_arr = []
      attr_actions.each_pair do |attr, action|
        raise 'Параметр(ы) команды <add_action_on_change> должен быть типа Symbol.' if attr.class != Symbol
        raise 'Параметр команды <add_action_on_change>, определяющий действие, должен быть задан.' if action == nil or action == ''
        if @attrs.has_key?(attr)
          if @attrs[attr].action != action
            @dh_inserted[:actions_on_change] << attr
            @attrs[attr].action = action
          end
        else
          ex_arr << attr.id2name
        end
      end
      if ex_arr.size > 0
        raise "Модуль #{@name.id2name} не содержит атрибут(ы) #{ex_arr.join(', ')}"
      end
    end

    def remove_action_on_change *attrs
      raise 'Команда <remove_action_on_change> доступна только при модификации существующего модуля командой <modify>.' if @new_object
      raise 'В команде <remove_action_on_change> должны быть указаны атрибуты' if attrs == nil
      ex_arr = []
      attrs.each do |attr|
        raise 'Параметр(ы) команды <remove_action_on_change> должен быть типа Symbol.' if attr.class != Symbol
        if @attrs.has_key?(attr)
          if @attrs[attr].action != nil
            @dh_removed[:actions_on_change] << attr
            @attrs[attr].action = nil
          end
        else
          ex_arr << attr.id2name
        end
      end
      if ex_arr.size > 0
        raise "Модуль #{@name.id2name} не содержит атрибут(ы) #{ex_arr.join(', ')}"
      end
    end

    def geo_sign *names
      raise 'Имя ЗС должно иметь тип Symbol' if names.any? {|it| it.class != Symbol }
      @geo_sign = names
      @dh_inserted[:geo_sign] = names unless @new_object
    end

    def self.get name
      $space.moduleAccount.modules[name]
    end

#    def self.get_module_def name
#	    name = symbol name # todo: если используется изнутри, будут проблемы
#      mod = $space.moduleAccount.modules[name]
#      mod.get_module_definition
#    end

#    def self.get_module_script name
#      mod = $space.moduleAccount.modules[name]
#      mod.get_module_script
#    end

    def self.each
      $space.moduleAccount.modules.each_pair { |name, mod| yield name, mod }
    end

    #def self.delete name
    #  each do |mod_name, user_module|
    #    unless mod_name == name
    #      if user_module.modules.index name
    #        Module.modify mod_name do
    #          remove_modules name
    #        end
    #      end
    #    end
    #  end
    #
    #  UserClass.each do |class_name, user_class|
    #    if user_class.modules.index name
    #      UserClass.modify class_name do
    #        remove_modules name
    #      end
    #    end
    #  end
    #
    #  $space.moduleAccount._delete name
    #end

    def self.delete name
      delete_internal name
    end

    def self.delete_internal name
      each do |module_name, user_module|
        unless module_name == name
          if user_module.modules.index name
            Module.module_eval "
                modify :#{module_name} do
                    remove_modules :#{name}
                end
            "
          end
        end
      end

      UserClass.each do |class_name, user_class|
        #TODO: Почему index?
        if user_class.modules.index name
          UserClass.class_eval "
            modify :#{class_name} do
              remove_modules :#{name}
            end
          "
          #UserClass.modify class_name do
          #  remove_modules_internal name
          #end
        end
      end

      $space.moduleAccount._delete name
    end

    # для внутреннего использования
    def self.has_module? name
      $space.moduleAccount.modules.has_key? name
    end

    # для внутреннего использования
    def self.get_module name
      $space.moduleAccount.modules[name]
    end

#    def self.get_by_const mod_const
#      $space.moduleAccount.modules.each_pair do |name, mod_def|
#        return mod_def if mod_def.dyn_module == mod_const
#      end
#      nil
#    end

# для внутреннего использования
    def self.get_methods sym_name
      cl = User.module_eval sym_name.id2name
      arr =cl.public_instance_methods
      arr.sort!
      arr
    end

    def self.get_module_methods module_name, array
      module_descriptor = Module.get module_name
      module_descriptor.methods.keys.each { |method_name| array << method_name }
      module_descriptor.modules.each { |name| Module.get_module_methods name, array }
      array
    end

    def get_state_mashines
      @state_mashines
    end

    def get_modules
      @modules
    end

    def get_attributes
      @attrs
    end

    def get_methods
      @methods
    end

    # @param mod [Module] Новый DSL создания данного модуля
    # @return [boolean] есть ли изменения
    def merge! mod
      changed = false
      # Описание
      if @descr != mod.get_description
        description mod.get_description
        changed ||= true
      end
      # Подсистемы
      if @subsystems != mod.get_subsystems
        @dh_inserted[:subsystems] = mod.get_subsystems - @subsystems
        @dh_removed[:subsystems] = @subsystems - mod.get_subsystems
        @subsystems = mod.get_subsystems
        changed ||= !@dh_inserted[:subsystems].empty? || !@dh_removed[:subsystems].empty?
      end
      # do_not_notify
      @external = mod.instance_variable_get(:@external)
      # Машины состояний
      if @state_mashines != mod.get_state_mashines
        @dh_inserted[:state_mashines] = mod.get_state_mashines - @state_mashines
        @dh_removed[:state_mashines] = @state_mashines - mod.get_state_mashines
        @state_mashines = mod.get_state_mashines
        changed ||= !@dh_inserted[:state_mashines].empty? || !@dh_removed[:state_mashines].empty?
      end
      # Модули
      if @modules != mod.get_modules
        @dh_inserted[:modules] = mod.get_modules - @modules
        @dh_removed[:modules] = @modules - mod.get_modules
        # Возможно ещё изменился порядок модулей.
        # Если в removed что-то есть, то всё равно будет полная перекомпиляция модуля
        if @dh_removed[:modules].empty?
          # Добавляем в removed специальный флаг вместо имени модуля, чтобы произошла полная перекомпиляция
          @dh_removed[:modules] << :_reorder_modules_flag_ unless mod.get_modules == (@modules + @dh_inserted[:modules])
        end
        @modules = mod.get_modules
        changed ||= !@dh_inserted[:modules].empty? || !@dh_removed[:modules].empty?
      end

      # Атрибуты
      @dh_inserted[:attrs] = mod.get_attributes.keys - @attrs.keys
      @dh_removed[:attrs] = @attrs.keys - mod.get_attributes.keys
      changed ||= !@dh_inserted[:attrs].empty? || !@dh_removed[:attrs].empty?
      # Удаляем удалённые атрибуты. Получаем в @attrs пересечение старых и новых атрибутов.
      @dh_removed[:attrs].each do |attr|
        @attrs.delete attr
      end
      # default_value
      def_values = Hash.new
      @attrs.each_key do |attr_name|
        def_values[attr_name] = mod.get_attributes[attr_name].def_value
      end
      change_default_value def_values
      changed ||= !@dh_inserted[:def_values].empty?
      # options
      @attrs.each do |attr_name, attr_descr|
        new_descr = mod.get_attributes[attr_name]
        if attr_descr.get_options != new_descr.get_options
          opt_hash = new_descr.get_options || Hash.new
          change_options attr_name, opt_hash
        end
      end
      changed ||= !@dh_inserted[:attr_options].nil? && !@dh_inserted[:attr_options].empty?
      # action_on_change
      actions_to_add = Hash.new
      actions_to_remove = []
      @attrs.each do |attr_name, attr_descr|
        new_action = mod.get_attributes[attr_name].action
        if attr_descr.action != new_action
          if new_action.nil?
            actions_to_remove << attr_name
          else
            actions_to_add[attr_name] = new_action
          end
        end
      end
      add_action_on_change actions_to_add
      remove_action_on_change *actions_to_remove
      changed ||= !@dh_inserted[:actions_on_change].empty? || !@dh_removed[:actions_on_change].empty?
      # Сохраняем атрибуты из нового модуля
      @attrs = mod.get_attributes

      # geo_sign
      geo_sign = mod.instance_variable_get(:@geo_sign)
      if @geo_sign != geo_sign
        @geo_sign = geo_sign
        @dh_inserted[:geo_sign] = geo_sign
        changed ||= true
      end
      # Методы
      if @methods != mod.get_methods
        # В removed попадают удалённые методы, а в inserted новые и изменённые.
        # Причем в @methods имена методов символы, а в removed и inserted почему-то строки.
        @dh_removed[:methods] = (@methods.keys - mod.get_methods.keys).map { |m| m.to_s }
        mod.get_methods.each do |name, meth|
          @dh_inserted[:methods] << name.to_s if meth != @methods[name]
        end
        @methods = mod.get_methods
        changed ||= !@dh_inserted[:methods].empty? || !@dh_removed[:methods].empty?
      end
      changed
    end
  end

  class MoveToModule
    def init
      @module_name = nil
    end
    def move_to modul_name
      @module_name = modul_name
    end
    def get_module_name
      @module_name
    end
  end
end