module User

  class UserObject < BaseDsl

    attr_accessor :class_name, :obj_id, :obj

    def initialize obj_id, new_object, space = :Main
      super nil, new_object
      @space = space
      @class_name = nil
      @new_class_name = nil
      @obj_id = obj_id
      @strg_id = nil
      @obj = nil
      unless @new_object
        @new_strg_id = nil
        @obj = $space[@space].objectAccount.objects[@obj_id]
        raise "Объекта с идент. #{@obj_id} не существует. Выполнение операции <modify> невозможно" unless @obj
        @strg_id = @obj.strg_id
      end
    end

    # Задает область действия объекта(scope).
    # @param scope[Symbol] :local, :account, :server
    # :local - нет в аккаунте, нет нотификаций, нет obj_id, нет strg_id
    # :account - есть в аккаунте, нет нотификаций, есть obj_id, есть strg_id
    # :server - есть в аккаунте, локальные(внутри сервера) нотификаций, есть obj_id, есть strg_id
    def scope scope
      @scope = scope
    end

    def into storage_name
      raise 'Выполнение операции <into> возможно только при создании объекта. Используйте оператор <move_to>' unless @new_object
      raise 'В команде <into> параметр должен иметь тип String' unless storage_name.class == String
      if storage_name
        # Здесь необходимо использовать основной Space, т.к. сториджи в сабспейсах сториджи создаются "на лету" на основании дескриптора,
        # хранящегося в аккаунте основного спейса
        if $space.storageAccount.storages.has_key? storage_name
          @strg_id = $space.storageAccount.storages[storage_name].strg_id
        else
          raise "Ошибка создания объекта. Не существует хранилища #{storage_name}"
        end
      end
    end

    def is class_name
      raise 'Оператор <is> доступен только в случае создания нового объекта. Используйте оператор <change_class>' unless @new_object
      raise 'В команде <is> параметр должен иметь тип Symbol' unless class_name.class == Symbol
      if class_name
        # Здесь необходимо использовать основной Space, т.к. дескрипторы классов в сабспейсах создаются "на лету" на основании дескриптора,
        # хранящегося в аккаунте основного спейса
        if $space.classAccount.classes.has_key? class_name
          @class_name = class_name
        else
          raise "Ошибка создания объекта. Не существует класса #{class_name}"
        end
      end
    end

    # todo: по-сути, это иллегальная операция. Смена класса у экземпляра объекта /в Jruby/ хоть и возможна (хакерскими методами), но при этом
    # теряются ВСЕ значения атрибутики объекта.
    def change_class class_name
      raise 'Оператор <change_class> доступен только в случае модификации существующего объекта. Используйте оператор <is>' if @new_object
      raise 'В команде <change_class> параметр должен иметь тип Symbol' unless class_name.class == Symbol
      if class_name
        # проверка выполняется таким образом, а не через аккаунт, т.к. некоторые имена классов используют префикс User, а некоторые - нет
        unless @obj.class.to_s == 'User::' + class_name.to_s
          @new_class_name = class_name
        else
          raise 'Ошибка задания класса объекта. Новый класс не отличается от старого'
        end
      else
        raise 'Ошибка задания класса объекта. Не задан класс объекта.'
      end
    end

    def build
      raise "Неверно задана область действия объекта(scope) объекта :#{@scope}" unless [:account, :server, :local, nil].include?(@scope)
      return build_local_obj if @scope == :local

      raise 'Для создания объекта обязательно должны быть заданы хранилище и класс' unless @strg_id && @class_name

      # Здесь необходимо использовать основной Space, т.к. дескрипторы классов в сабспейсах создаются "на лету" на основании дескриптора,
      # хранящегося в аккаунте основного спейса
      dyn_class = $space.classAccount.classes[@class_name].dyn_class
      raise "Ошибка создания объекта. Возможно ошибка в описании класса #{@class_name}" unless dyn_class

      obj = dyn_class.new
      obj.set_strg_id @strg_id

      obj.scope = @scope if @scope
      $space[@space].objectAccount._insert @strg_id, @class_name, obj
      obj
    end

    def build_local_obj
      raise 'Для создания объекта обязательно должны быть заданы класс' unless @class_name
      dyn_class = $space.classAccount.classes[@class_name].dyn_class
      raise "Ошибка создания объекта. Возможно ошибка в описании класса #{@class_name}" unless dyn_class

      obj = dyn_class.new
      obj.space = :Null
      obj.scope = :local
      obj
    end

    def move_to new_storage_name
      raise 'Выполнение операции <move_to> возможно только при модификации раннее созданного объекта' if @new_object
      raise 'В команде <move_to> параметр должен иметь тип String' unless new_storage_name.class == String
      # Здесь необходимо использовать основной Space, т.к. сториджи в сабспейсах сториджи создаются "на лету" на основании дескриптора,
      # хранящегося в аккаунте основного спейса
      storage = $space.storageAccount.storages[new_storage_name]
      if storage
        @new_strg_id = storage.strg_id
      else
        raise "Ошибка перемещения объекта. Не существует хранилища #{new_storage_name}"
      end
    end

    def update
      if @obj && @obj_id && @new_strg_id && @new_class_name.nil?
        # Изменили только хранилище
        $space[@space].objectAccount._move_to(@obj, @new_strg_id)
        return
      end
      $space[@space].objectAccount._update @obj, @obj_id, @new_strg_id, @new_class_name if @obj and @obj_id
    end

    def self.create space = :Main, &block
      user_object = UserObject.new nil, true, space
      user_object.instance_eval &block
      instance = user_object.build
      instance
    end

    def self.replicate(obj)
      storage_id = obj.strg_id
      class_name = obj.class.to_s.sub(/User::/, '').to_sym
      $space[obj.space].objectAccount._sync storage_id, class_name, obj
    end

    # Для методов - пользовательских сеттеров.
    def self.build class_name, storage_name, attrs = Hash.new, scope = nil, &block
      # Здесь необходимо использовать основной Space, т.к. дескрипторы классов в сабспейсах создаются "на лету" на основании дескриптора,
      # хранящегося в аккаунте основного спейса
      dyn_class = $space.classAccount.classes[class_name].dyn_class
      storage = $space.storageAccount.storages[storage_name]
      obj = dyn_class.new
      obj.set_strg_id storage.strg_id
      obj.scope = scope if scope
      $space[:Empty].objectAccount._insert obj.strg_id, class_name, obj

      attrs.each_pair do |attr_name, attr_value|
        next unless attr_name && attr_value
        next unless obj.respond_to? attr_name
        obj.send attr_name, attr_value
      end

      yield obj if block_given?

      $space.objectAccount.move obj, obj.strg_id

      obj
    rescue Exception => err
      # В результате ошибок в EmptySpace могут накапливаться объекты
      $space[:Empty].rollback rescue nil
      raise "Для создания объекта должны быть заданы хранилище и класс" unless storage_name && class_name
      raise "Ошибка создания объекта. Возможно ошибка в описании класса #{class_name}" unless dyn_class
      raise "Ошибка создания объекта. Не существует хранилища #{storage_name}" unless storage
      raise err
    end

    # Для системных сеттеров
    def self.construct class_name, storage_name, attrs = Hash.new, scope = nil, &block
      # Здесь необходимо использовать основной Space, т.к. дескрипторы классов в сабспейсах создаются "на лету" на основании дескриптора,
      # хранящегося в аккаунте основного спейса
      dyn_class = $space.classAccount.classes[class_name].dyn_class
      storage = $space.storageAccount.storages[storage_name]
      obj = dyn_class.new
      obj.set_strg_id storage.strg_id
      obj.scope = scope if scope
      $space[:Empty].objectAccount._insert obj.strg_id, class_name, obj

      attrs.each_pair do |attr_name, attr_value|
        next unless attr_name && attr_value
        # Достаточно провериться на оригинальный атрибут, т.к. метод с суфиксом "=" генерится автоматически
        next unless obj.respond_to? attr_name
        obj.send "#{attr_name}=", attr_value
      end

      yield obj if block_given?

      $space.objectAccount.move obj, obj.strg_id

      obj
    rescue Exception => err
      # В результате ошибок в EmptySpace могут накапливаться объекты
      $space[:Empty].rollback rescue nil
      raise "Для создания объекта должны быть заданы хранилище и класс" unless storage_name && class_name
      raise "Ошибка создания объекта. Возможно ошибка в описании класса #{class_name}" unless dyn_class
      raise "Ошибка создания объекта. Не существует хранилища #{storage_name}" unless storage
      raise err
    end

    # Для системных методов инжектирования значения
    def self.___construct class_name, storage_name, attrs = Hash.new, scope = nil, &block
      # Здесь необходимо использовать основной Space, т.к. дескрипторы классов в сабспейсах создаются "на лету" на основании дескриптора,
      # хранящегося в аккаунте основного спейса
      dyn_class = $space.classAccount.classes[class_name].dyn_class
      storage = $space.storageAccount.storages[storage_name]
      obj = dyn_class.new
      obj.set_strg_id storage.strg_id
      obj.scope = scope if scope
      $space[:Empty].objectAccount._insert obj.strg_id, class_name, obj

      attrs.each_pair do |attr_name, attr_value|
        next unless attr_name && attr_value
        # Достаточно провериться на оригинальный атрибут, т.к. метод с префиксом "___" генерится автоматически
        next unless obj.respond_to? attr_name
        obj.send "___#{attr_name}=", attr_value
      end

      yield obj if block_given?

      $space.objectAccount.move obj, obj.strg_id

      obj
    rescue Exception => err
      # В результате ошибок в EmptySpace могут накапливаться объекты
      $space[:Empty].rollback rescue nil
      raise "Для создания объекта должны быть заданы хранилище и класс" unless storage_name && class_name
      raise "Ошибка создания объекта. Возможно ошибка в описании класса #{class_name}" unless dyn_class
      raise "Ошибка создания объекта. Не существует хранилища #{storage_name}" unless storage
      raise err
    end

    def self.modify obj_id, space = :Main, &block
      raise 'Необходимо задать идентификатор объекта в команде <modify>' unless obj_id
      userObj = UserObject.new obj_id, false, space
      userObj.instance_eval &block
      userObj.update
    end

    def self.get obj_id, space = :Main
      $space[space].objectAccount.objects[obj_id]
    end

    def self.each space = :Main
      $space[space].objectAccount.objects.each_pair do |obj_id, obj|
        yield obj_id, obj
      end
    end

    def self.each_in_storage strg_id, space = :Main
      Storage.each_object_by_id(strg_id, space) do |obj_id, obj|
        yield obj_id, obj
      end
    end

    def self.del_object obj
      space = obj.respond_to?(:space) ? obj.space : :Main
      $space[space].objectAccount._delete obj.obj_id, obj.strg_id
    end

    def self.del_object_by_id obj_id, space = :Main
      strg_id = get(obj_id, space).strg_id rescue nil
      $space[space].objectAccount._delete obj_id, strg_id
    end

    def self.del_objects_in_storage name, space = :Main
      stg = $space[space].storageAccount.storages[name]
      stg.objects.each_pair do |obj_id, object|
        $space[space].objectAccount._delete obj_id, object.strg_id
      end if stg
    end

    def self.get_objects_in_storage name, space = :Main
      stg = $space[space].storageAccount.storages[name]
      stg.objects.each_value do |object|
        yield object
      end if stg
    end

    def self.add object, space_name, strg_id = nil
      $space[space_name].objectAccount.add object, strg_id
    end

    def self.move object, space_name, strg_id = nil
      $space[space_name].objectAccount.move object, strg_id
    end

    # Пересоздание экземпляров всех модулей, классов и объектов.
    # Применяется после модификации модулей и классов при $update_classes_dynamically = false.
    def self.rebuild_all
      # Сохраняем все объекты в дампах
      # пока считаем все спейсы загруженными. todo:
      obj_dumps = Hash.new
      $space.each do |space_name, space|
        next if space_name == :Null
        space_dumps = []
        User::UserObject.each space_name do |obj_id, obj|
          begin
            space_dumps << Marshal.dump(obj)
          rescue Exception => err
            $log.warn "Ошибка создания дампа объекта obj_id = #{obj_id}: #{err}"
          end
        end
        obj_dumps[space_name] = space_dumps unless space_dumps.empty?
      end
      # Удаляем классы
      UserClass.each do |class_name, class_descr|
        class_descr.undef_class
      end
      # Удаляем модули
      Module.each do |module_name, module_descr|
        module_descr.undef_module
      end
      # Создаём модули
      Module.each do |module_name, module_descr|
        begin
          module_descr.user_module_eval
        rescue Exception => err
          $log.warn "Ошибка создания модуля #{module_name}: #{err}"
          RubyModuleUtil.remove_const module_name, User
        end
      end
      # Создаём классы
      UserClass.each do |class_name, class_descr|
        begin
          class_descr.user_class_eval
        rescue Exception => err
          $log.warn "Ошибка создания класса #{class_name}: #{err}"
          RubyModuleUtil.remove_const class_name, User
        end
      end
      # Восстанавливаем объекты из дампов
      # Спорно!!! todo:
      obj_dumps.each do |space_name, space_dumps|
        obj_account = $space[space_name].objectAccount
        strg_account = $space[space_name].storageAccount
        class_account = $space[space_name].classAccount
        space_dumps.each do |obj_dump|
          begin
            obj = Marshal.load obj_dump
            obj_account.objects[obj.obj_id] = obj
            strg = strg_account.storage_list[obj.strg_id]
            strg.objects[obj.obj_id] = obj if strg
            class_descr = class_account.classes[ClassAccount.object_class_name obj]
            class_descr.objects[obj.obj_id] = obj if class_descr
          rescue Exception => err
            $log.warn "Ошибка восстановления из дампа объекта obj_id = #{obj_id}: #{err}"
          end
        end
      end
      # Синхронизируем атрибуты объектов с их новыми классами
      $space.each do |space_name, space_descr|
        Attribute.synchronize_objects_to_class nil, space_name
      end
    end

    # Поиск UserObject по значению атрибута (опционально в хранилище и/или по классу)
    # @param attr_name [String] Имя атрибута
    # @param attr_val [Object] Значение атрибута
    # @param storage_name [String] Имя хранилеща
    # @param class_name [String] Имя класса
    def self.get_by_attr_val attr_name, attr_val, storage_name = nil, class_name = nil, space = :Main
      raise 'Имя атрибута (первый параметр) задается текстом (без двоеточия)' unless attr_name.class == String
      raise 'Имя хранилища (третий параметр) задается текстом' unless (storage_name.class == String || !storage_name)
      raise 'Имя класса (четвертый параметр) задается текстом (без двоеточия)' unless (class_name.class == String || !class_name)
      raise "Класс #{class_name} не существует" unless (!class_name || $space.classAccount.classes.has_key?(class_name.to_sym))
      storage = nil
      if storage_name
        storage = User::Storage.get_by storage_name, space
        raise "Хранилище #{storage_name} не существует" unless storage
      end
      arr_object = []
      if storage_name && class_name
        # поиск по хранилищу, классу, имени и значению атрибута:
        storage.objects.each_value do |obj|
          arr_object << obj if (obj.class.to_s == 'User::' + class_name && obj.respond_to?(attr_name) && obj.send(attr_name) == attr_val)
        end
      elsif storage_name
        # поиск по объектам в хранилище, имени и значению атрибута:
        storage.objects.each_value do |obj|
          arr_object << obj if (obj.respond_to?(attr_name) && obj.send(attr_name) == attr_val)
        end
      elsif class_name
        # поиск по объектам от класса, имени и значению атрибута:
        User::UserClass.each_object(class_name.to_sym, space) do |obj_id, obj|
          arr_object << obj if (obj.respond_to?(attr_name) && obj.send(attr_name) == attr_val)
        end
      else
        # поиск по имени и значению атрибута:
        User::UserObject.each space do |obj_id, obj|
          arr_object << obj if (obj.respond_to?(attr_name) && obj.send(attr_name) == attr_val)
        end
      end
      case arr_object.size
        when 0 then
          nil
        when 1 then
          arr_object[0]
        else
          arr_object
      end
    end

    def get_id
      @obj_id
    end

  end

  # Псевдоним
  def self.объект obj_id, space = :Main
  UserObject.get obj_id, space
  end

end