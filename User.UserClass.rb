module User

  class UserClass < BaseDsl

    attr_reader :name, :super_class, :new_object

    # @param updating [boolean] выполняется UserClass.update
    def initialize name, new_object, updating = false
      super name, new_object

      #puts "!!! UserClass = #{name}"
      if @new_object
        if !updating && $space.classAccount.classes.has_key?(@name)
          raise "Класс #{@name.id2name} уже существует. Выполнение операции <create> с указанным именем невозможно"
        end
        @modules = []
        @state_mashines = []
        @super_class = nil
      else
        if !$space.classAccount.classes.has_key?(@name)
          raise "Класса #{@name.id2name} не существует. Выполнение операции <modify> невозможно"
        end
        @dh_inserted[:modules]=[]
        @dh_inserted[:state_mashines]=[]
        @dh_inserted[:super_class]=nil
        @dh_inserted[:descr]=''

        @dh_removed[:modules]=[]
        @dh_removed[:state_mashines]=[]
        @dh_removed[:super_class]=nil
        @dh_removed[:descr]=''

        #Получить все данные по старому классу. C "глубоким" копированием
        class_def = $space.classAccount.class_defs[@name]
        if class_def[0] == nil
          @super_class = nil
        else
          @super_class = Marshal.load(Marshal.dump(class_def[0]))
        end
        if class_def[1] == nil
          @modules = []
        else
          @modules = Marshal.load(Marshal.dump(class_def[1]))
        end

        if class_def[2] == nil
          @state_mashines = []
        else
          @state_mashines = Marshal.load(Marshal.dump(class_def[2]))
        end


        if class_def[3] == nil
          @descr = ''
        else
          @descr = Marshal.load(Marshal.dump(class_def[3]))
        end
        @subsystems = class_def[4] || []
        data_holder = Marshal.load(Marshal.dump(class_def[5])) || Hash.new
        @table = data_holder[:table]
      end
      #puts self
      #puts self.class
    end

    def is super_class
      raise "Неверный формат параметра команды <is>. Пример использования \"is :DefaultTreeModel\"" unless super_class.nil? || super_class.class == Symbol
      unless @new_object
        return if super_class == @super_class
        if @super_class
          if super_class
            # замену одного на другое считаем вставкой
            @dh_inserted[:super_class] = super_class
          else
            # было и теперь не будет - чистое удаление
            @dh_removed[:super_class] = super_class
          end
        else
          # не было и теперь будет - чистая вставка
          @dh_inserted[:super_class] = super_class
        end
      end
      @super_class = super_class
    end

    def add_state_mashine sm
      mod_name = 'SM_' + sm.to_s
      raise "StateMashine #{sm} не существует или её модуль не был построен" unless $space.moduleAccount.modules.has_key? mod_name.intern
      raise "Класс #{@name.id2name} уже содержит машину состояний #{sm.to_s}" if @state_mashines.find { |el| el == sm }
      @state_mashines << sm
      @dh_inserted[:state_mashines] << sm unless @new_object
    end
    alias add_state_machine add_state_mashine

    def add_state_mashines *sms
      sms.each { |sm| add_state_mashine sm }
    end
    alias add_state_machines add_state_mashines

    def remove_state_mashines *sms
      raise 'Команда remove_state_mashines доступна только при модификации существующего класса командой modify.' if @new_object
      sms.each do |sm|
        if @state_mashines.find{|el| el == sm}
          @state_mashines.delete sm
          @dh_removed[:state_mashines] << sm
        else
          raise "Класс #{@name.id2name} не содержит машины состояний #{sm.to_s}"
        end
      end
    end
    alias remove_state_machines remove_state_mashines

    def state_mashines *sms
      raise "Команда <state_mashines> доступна только при создании нового класса командой <create>. \nНеобходимо использовать команду <add_state_mashines>" unless @new_object
      sms.each { |sm| add_state_mashine sm }
    end
    alias state_machines state_mashines

    def modules *names
      raise "Команда <modules> доступна только при создании нового класса командой <create>. \nНеобходимо использовать команду <add_modules>" unless @new_object
      names.each { |name| @modules.push name }
    end

    def add_modules *names
      raise "Команда <add_modules> доступна только при модификации существующего класса командой <modify>. \nНеобходимо использовать команду <modules>" if @new_object

      ex_arr = []
      names.each do |name|
        if @modules.find{ |el| el == name }
          ex_arr << name.id2name
        else
          @modules.push name
          @dh_inserted[:modules] << name
        end
      end
      raise "Класс #{@name} уже содержит модул(ь/и) #{ex_arr.join(', ')}" unless ex_arr.empty?
    end

    def remove_modules *names
      raise "Команда <remove_modules> доступна только при модификации существующего класса командой <modify>. \nНеобходимо использовать команду <modules>" if @new_object
      names.collect! { |name| name }
      remove_modules_internal *names
    end

    def remove_modules_internal *names
      raise "Команда <remove_modules> доступна только при модификации существующего класса командой <modify>. \nНеобходимо использовать команду <modules>" if @new_object

      ex_arr = []
      names.each do |name|
        if @modules.find{ |el| el == name }
          @dh_removed[:modules] << name
          @modules.delete(name)
        else
          ex_arr << name.id2name
        end
      end
      raise "Класс #{@name} не содержит модул(ь/и) #{ex_arr.join(', ')}" unless ex_arr.empty?
    end

    # @param table [String] Имя таблицы в БД, которая описывается этим классом для ORM
    def table table
      raise 'Неверный формат команды <table>. Имя таблицы должно иметь тип String.' unless table.nil? || table.class == String
      @table = table
      @dh_inserted[:table] = table unless @new_object
    end

    def insert
      dh = Hash.new
      dh[:table] = @table
      $space.classAccount._insert @name, @super_class, @modules, @state_mashines, @descr, @subsystems, dh if @new_object
    end

    def update
      dh = Hash.new
      dh[:table] = @table
      $space.classAccount._update @name, @super_class, @modules, @state_mashines, @dh_classified, @descr, @subsystems, dh unless @new_object
    end

    def self.recreate name, &block
      delete name rescue nil
      create name, &block
    end

    def self.create name, &block
      raise 'Ошибка формата команды. Пропущен блок do ... end или { ... }' unless block_given?
      raise 'Неверный формат параметра команды <create>. Имя класса имеет тип Symbol :DefaultTreeModel' unless name.class == Symbol
      user_class = UserClass.new name, true
      user_class.instance_eval &block
      user_class.insert
    end

    def self.modify name, &block
      raise 'Ошибка формата команды. Пропущен блок do ... end или { ... }' unless block_given?
      raise 'Неверный формат параметра команды <modify>. Имя класса имеет тип Symbol :DefaultTreeModel' unless name.class == Symbol
      user_class = UserClass.new name, false
      user_class.instance_eval &block
      user_class.update
    end

    # Аналог recreate, но без пересоздания класса
    def self.update name, &block
      # Если класса нет, то просто выполняем UserClass.create
      return create name, &block unless get(name)
      raise 'Ошибка формата команды. Пропущен блок do ... end или { ... }' unless block_given?
      raise 'Неверный формат параметра команды <modify>. Имя класса имеет тип Symbol :DefaultTreeModel' unless name.class == Symbol
      new_class = UserClass.new name, true, true
      new_class.instance_eval(&block)
      old_class = UserClass.new name, false
      changed = old_class.merge! new_class
      old_class.update if changed
    end

    def self.each space = :Main
      $space[space].classAccount.classes.each_pair do |name, class_def|
        yield name, class_def
      end
    end

    def self.get_class_def name
      cl = $space.classAccount.classes[name]
      cl.get_class_definition
    end

    def self.get_class_script name
      cl = $space.classAccount.classes[name]
      cl.get_class_script
    end

    def self.delete name
      $space.classAccount._delete name
    end

    def self.delete_without_objects name, space = :Main
      $space[space].classAccount._delete name
    end

    def self.delete_with_objects name, space = :Main
      descriptor = get name
      raise "Класс с именем #{name} не определен" unless descriptor
      clazz = descriptor.dyn_class

      # Дескрипторы классов содержат хэш объектов, созданных от данного класса, поэтому в различных спейсах существуют различные экземпляры таких дескрипторов.
      # В случае, если удаление класса происходит в основном спейсе :Main, - удаляем дескрипторы класса (с объектами) так-же во всех сабспейсах. Если же задан
      # другой спейс, то определение класса и объекты удаляем только в нем.
      if space == :Main
        $space.spaces.each_value { |space| delete_clazz_with_objects clazz, name, space }
      else
        delete_clazz_with_objects clazz, name, space
      end
    end

    def self.delete_clazz_with_objects clazz, name, space = :Main
      # todo: возможно эта конструкция не рабочая (ConcurrentModifycation) и следует использовать delete_if
      $space[space].objectAccount.objects.each_pair do |obj_id, obj|
        if obj.class == clazz
          $space[space].objectAccount._delete obj_id, obj.strg_id
        end
      end

      # todo: не удаляется рантайм-определение руби-класса в модуле User
      $space[space].classAccount._delete name
    end

    def self.get class_name, space = :Main
      $space[space].classAccount.classes[class_name]
    end

    # *class_name* Symbol Имя класса (без User::)
    # *return* Array(UserClass) Массив описаний классов наследников указанного класса, вместе с ним самим
    def self.get_with_inheritors class_name
      result = []
      class_def = get class_name
      return result unless class_def
      $space.classAccount.classes.each_value do |cl_def|
        result << cl_def if class_def.dyn_class <= cl_def.dyn_class
      end
      result
    end

    def self.get_number_objects class_name, space = :Main
      class_def = get class_name, space
      class_def ? class_def.count_objects : 0
    end

    def self.get_methods class_name
      begin
        cl = User.module_eval class_name.to_s
        arr = cl.public_instance_methods - Object.methods
        arr.sort!
      rescue NameError => err
        arr = [err.message]
      end
      arr
    end

    def self.get_class_methods class_name
      array = []
      UserClass.get(class_name).modules.each { |module_name| Module.get_module_methods module_name, array }
      array.sort! { |a, b| a.to_s <=> b.to_s }
    end

    # Итерация по всем объектам экземплярам указанного класса {|obj_id, obj| ...}
    # *class_name* Symbol Имя класса (без User::)
    # *with_inheritors* true/false с учетом наследования
    def self.each_object class_name, with_inheritors = false, space = :Main
      objects(class_name, with_inheritors, space).each_pair do |obj_id, obj|
        yield obj_id, obj
      end
    end

    # *class_name* Symbol Имя класса (без User::)
    # *with_inheritors* true/false с учетом наследования
    # *return* Hash(Fixnum id объекта => объект) Хэш объектов экземпляров указанного класса
    def self.objects class_name, with_inheritors = false, space = :Main
      result = Hash.new
      if with_inheritors
        # определения классов можно извлекать из основного спейса
        class_defs = get_with_inheritors class_name
        class_defs.each do |cl_def|
          # выполняем перевыборку из указанного спейса
          result.merge! get(cl_def.name, space).objects
        end
      else
        class_def = get class_name, space
        return class_def.objects if class_def
      end
      result
    end

    def get_state_mashines
      @state_mashines
    end

    def get_modules
      @modules
    end

    def get_table
      @table
    end

    # @param cl [User::UserClass] Новый DSL создания данного класса
    # @return [boolean] есть ли изменения
    def merge! cl
      changed = false
      # Описание
      if @descr != cl.get_description
        description cl.get_description
        changed ||= true
      end
      # Подсистемы
      if @subsystems != cl.get_subsystems
        @dh_inserted[:subsystems] = cl.get_subsystems - @subsystems
        @dh_removed[:subsystems] = @subsystems - cl.get_subsystems
        @subsystems = cl.get_subsystems
        changed ||= !@dh_inserted[:subsystems].empty? || !@dh_removed[:subsystems].empty?
      end
      # super_class
      if @super_class != cl.super_class
        is cl.super_class
        changed ||= true
      end
      # Машины состояний
      if @state_mashines != cl.get_state_mashines
        @dh_inserted[:state_mashines] = cl.get_state_mashines - @state_mashines
        @dh_removed[:state_mashines] = @state_mashines - cl.get_state_mashines
        @state_mashines = cl.get_state_mashines
        changed ||= !@dh_inserted[:state_mashines].empty? || !@dh_removed[:state_mashines].empty?
      end
      # Модули
      if @modules != cl.get_modules
        @dh_inserted[:modules] = cl.get_modules - @modules
        @dh_removed[:modules] = @modules - cl.get_modules
        # Возможно ещё изменился порядок модулей.
        # Если в removed что-то есть, то всё равно будет полная перекомпиляция класса
        if @dh_removed[:modules].empty?
          # Добавляем в removed специальный флаг вместо имени модуля, чтобы произошла полная перекомпиляция
          @dh_removed[:modules] << :_reorder_modules_flag_ unless cl.get_modules == (@modules + @dh_inserted[:modules])
        end
        @modules = cl.get_modules
        changed ||= !@dh_inserted[:modules].empty? || !@dh_removed[:modules].empty?
      end
      # table
      if @table != cl.get_table
        table cl.get_table
        changed ||= true
      end
      changed
    end

  end
end