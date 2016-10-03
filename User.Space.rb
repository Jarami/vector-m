include Java

require File.dirname(__FILE__) + '/../commons/delegate.rb'
require File.dirname(__FILE__) + '/../commons/event/event_service'

require File.dirname(__FILE__) + '/account/access_rights_account'
require File.dirname(__FILE__) + '/account/binary_account'
require File.dirname(__FILE__) + '/account/settings_account'
require File.dirname(__FILE__) + '/account/jobs_account'
require File.dirname(__FILE__) + '/account/class_account'
require File.dirname(__FILE__) + '/account/gui_account'
require File.dirname(__FILE__) + '/account/message_account'
require File.dirname(__FILE__) + '/account/message_pattern_account'
require File.dirname(__FILE__) + '/account/model_account'
require File.dirname(__FILE__) + '/account/module_account'
require File.dirname(__FILE__) + '/account/object_account'
require File.dirname(__FILE__) + '/account/property_account'
require File.dirname(__FILE__) + '/account/role_account'
require File.dirname(__FILE__) + '/account/space_account'
require File.dirname(__FILE__) + '/account/space_pattern_account'
require File.dirname(__FILE__) + '/account/storage_account'
require File.dirname(__FILE__) + '/account/topopogy_account'
require File.dirname(__FILE__) + '/account/user_account'
require File.dirname(__FILE__) + '/account/user_group_account'
require File.dirname(__FILE__) + '/account/workflow_account'
require File.dirname(__FILE__) + '/account/plugin_account'
require File.dirname(__FILE__) + '/account/u_storage_account'
require File.dirname(__FILE__) + '/account/u_object_account'
require File.dirname(__FILE__) + '/account/reports_account'
require File.dirname(__FILE__) + '/account/null_account'

require File.dirname(__FILE__) + '/account/sub/class_sub_account'
require File.dirname(__FILE__) + '/account/sub/object_sub_account'
require File.dirname(__FILE__) + '/account/sub/property_sub_account'
require File.dirname(__FILE__) + '/account/sub/storage_sub_account'

require File.dirname(__FILE__) + "/account/empty/class_empty_account"
require File.dirname(__FILE__) + "/account/empty/object_empty_account"
require File.dirname(__FILE__) + "/account/empty/property_empty_account"
require File.dirname(__FILE__) + "/account/empty/storage_empty_account"

module User
  # Спейс - черная дыра(аналог /dev/null). Не распростаняет никаких нотификаций, не пишет в базу.
  # Используется для локальных(scope == :local) пользовательских объектов.
  class NullSpace
    attr_reader :propertyAccount, :objectAccount
    attr_reader :name

    def initialize
      @name = :Null

      @propertyAccount = Object.new
      # Заглушки-методы для propertyAccount
      def @propertyAccount._update(obj_id, strg_id, prp_name, value, _obj = nil, complex_prp_path = [prp_name.to_sym], external = false, _ntf = nil, source = nil)
        # stub
      end

      def @propertyAccount._insert(obj_id, strg_id, prp_name, value, _obj = nil, complex_prp_path = [prp_name.to_sym], external = false, _ntf = nil)
        # stub
      end

      def @propertyAccount._delete(obj_id, strg_id, prp_name, _obj = nil, complex_prp_path = [prp_name.to_sym], external = false, _ntf = nil)
        # stub
      end

      def @propertyAccount.subscribe subscriber, filter = nil
        # stub
      end

      def @propertyAccount.unsubscribe subscriber, filter = nil
        # stub
      end

      @objectAccount = Object.new
      # Заглушки-методы для objectAccount

      # Считаем что в NullSpace объектов нет
      def @objectAccount.objects
        {}
      end

    end

    def set_data_provider data_provider
    end

    def set_concept_data_provider data_provider
    end

  end


  #noinspection RubyInstanceVariableNamingConvention
  class SubSpace
    # Прокси для всех остальных аккаунтов и методов стандартного DM
    include Delegate

    attr_reader :monitor, :name, :accounts
    attr_reader :storageAccount, :classAccount, :objectAccount, :propertyAccount
    # Сервис сообщений собственный в каждом спейсе, однако другие сервисы, в т.ч. работающие с данным спейсом могут
    # использовать в зависимости от целей как данный сервис, так и сервис сообщений пространства :Main
    attr_reader :event_service
    # Заглушка. Аналог dev null
    attr_reader :nullAccount

    # @param monitor [OnlineMonitor]
    # @param name [Symbol] - имя данного спейса
    # @param main_space [MainSpace] - ссылка на основной спейс приложения
    # @param pattern [SpacePattern] - шаблон соответствующего спейса
    def initialize monitor, name, main_space = nil, pattern = nil
      # делегируем обработку всех неопределенных вызовов основному пространству данных.
      # при вызове super в нашем классе так-же будут определены атрибут @main_space и метод main_space
      super main_space, :main_space

      @log = $log
      @event_service = SpaceEventService.new
      @log.debug 'Инициализация общей модели данных ...'
      @monitor = monitor
      @name = name
      @data_provider = EmptyDataProvider.new
      @concept_data_provider = @data_provider
      @accounts = Hash.new

      create_class_map
      create_accounts

      # Если передан дескриптор шаблона, настроим аккаунты в соответствии с его описанием
      if pattern
        # Если данные аккаунтов спейса являются локальными (не должны реплицироваться), переопределим метод EntityAccount.dispatch ntf.
        @accounts.each_value { |account| account.instance_eval %q/class << account; define_method(:dispatch) {|_|} end/ } if pattern.local
        # Если данные сохраненного спейса не должны изменяться в БД
        # Локальный спейс всегда без автокоммита - он для него не имеет смысла
        @accounts.each_value { |account| account.instance_eval %q/class << account; define_method(:save) {|_|} end/ } unless pattern.autocommit
      end

      # Кэшированное значение списка моделей на основании которого был загружен ObjectAccount. Используется для перезагрузки спейсов.
      @models_list = nil
    end

    def create_class_map
      @classes = Hash[
        :storageAccount 	=> StorageSubAccount,
        :classAccount 		=> ClassSubAccount,
        :objectAccount 		=> ObjectSubAccount,
        :propertyAccount 	=> PropertySubAccount,
        :nullAccount      => NullAccount
      ]
    end

    def create_accounts
      # для данного набора важна последовательность создания
      create_account :storageAccount, 'Хранилища объектов'
      create_account :classAccount, 'Реестр классов системы'
      create_account :objectAccount, 'Учёт объектов системы', 					@storageAccount, @classAccount
      create_account :propertyAccount, 'Учёт свойств объектов системы', 	@storageAccount
      create_account :nullAccount, 'dev/null'
    end

    def create_account account_name, description, *accounts
      definitions, arguments = Delegate.to_str accounts, :accounts
      arguments << ', ' unless arguments.empty?
      instance_eval %Q/#{definitions}@accounts[account_name] = @#{account_name} = @classes[account_name].new(#{arguments}:#{account_name}, description + " '" + @name.to_s + "'")/
      instance_eval %Q/@#{account_name}.space = @name/
    end

    def set_data_provider data_provider
      @data_provider = data_provider
      @accounts.each_value { |account| account.set_data_provider @data_provider }
    end

    def set_concept_data_provider data_provider
      @concept_data_provider = data_provider
      @accounts.each_value { |account| account.set_concept_data_provider @concept_data_provider }
    end

    def rollback
      @accounts.each_value { |account| account.rollback_internal unless account == @objectAccount }
      # должен откатываться последним
      @objectAccount.rollback_internal
    end

    def commit
      @accounts.each_value { |account| account.commit_internal unless account == @objectAccount }
      # должен коммититься последним
      @objectAccount.commit_internal
    end

    ACCOUNT_CLEANUP_ORDER = [:propertyAccount, :objectAccount, :storageAccount, :classAcount, :nullAccount]

    def self_delete
      # останавливаем обработку нотификаций переопределением метода, затем "разбираем" все аккаунты
      @accounts.each_value { |account| account.instance_eval %q/class << account; define_method(:handle) {|_|} end/ }
      ACCOUNT_CLEANUP_ORDER.each do |account_key|
        account = @accounts[account_key]
        account.self_delete if account and account.respond_to? :self_delete
      end

      @accounts.clear

      @monitor = nil
      @data_provider = EmptyDataProvider.new
      @concept_data_provider = @data_provider
    end

    def account_descr sym_name
      account = @accounts[sym_name]
      account ? account.description : @main_space ? @main_space.account_descr(sym_name) : 'Не определено'
    end

    def get_objects_by_strg strg_id
      arr = []
      strg = @storageAccount.get(strg_id)
      return arr unless strg
      strg.objects.each_value do |obj|
        # Перестраховка
        next unless obj.strg_id == strg_id
        # Не загружаем локальные объекты
        next if obj.scope
        arr << obj
      end
      arr
    end

    def print_data_model
      ObjectSpace.each_object(Class) { |clazz| @log.debug clazz if clazz.to_s =~ /\AUser/ }
    end

    def load_data models_list = nil
      @models_list = models_list if models_list
      @objectAccount.load @models_list
    end

    # @return [SubSpace]
    def clone &block
      descriptor = Space.clone_internal @name, &block
      $space[descriptor.name]
    end

    def dump_stat
      @accounts.each_value { |account| account.dump_stat if account.respond_to?(:dump_stat) }
    end

  end

  class EmptySpace < SubSpace

    def initialize monitor, name, main_space = nil, pattern = nil
      super
    end

    def create_class_map
        @classes = Hash[
          :storageAccount 	=> StorageEmptyAccount,
          :classAccount 		=> ClassEmptyAccount,
          :objectAccount 		=> ObjectEmptyAccount,
          :propertyAccount 	=> PropertyEmptyAccount,
          :nullAccount      => NullAccount
        ]
    end
  end

  require File.dirname(__FILE__) + "/account/sub/sub_account_util"

  # Пространство данных.
  #
  # Любой сервер или приложение запускается в некотором пространстве данных, определяемом в конфигурации.
  # Вводится понятие основного пространства данных сервера (с именем :Main) в котором происходит работа по-умолчанию.
  # В :Main существуют аккаунты всех сущностей системы. В других пространствах данных, в зависимости от реализации,
  # могут существовать лишь некоторые аккаунты, к примеру [:storageAccount, :objectAccount, :propertyAccount].
  # В этом случае такое пространство использует недостающие аккаунты из :Main
  #noinspection RubyInstanceVariableNamingConvention,RubyCodeStyle,RubyArgCount
  class MainSpace < SubSpace

    attr_reader :topologyAccount, :moduleAccount, :modelAccount, :workflowAccount, :guiAccount
    attr_reader :binaryAccount, :messagePatternAccount, :messageAccount, :settingsAccount, :jobsAccount
    attr_reader :userAccount, :userGroupAccount, :accessRightAccount, :roleAccount
    attr_reader :spacePatternAccount, :spaceAccount, :pluginAccount
    attr_reader :storageAccount, :ustorageAccount, :uobjectAccount, :reportAccount

    attr_reader :spaces

    def initialize monitor, name = :Main
      super
      # Выставляем себя в качестве значения по-умолчанию, таким образом данный спейс нельзя будет удалить из отображения
      # и он будет возвращаться на любое неизвестное имя
      @spaces = MasterProxyHash.new self
      @spaces[:Main] = self
      @spaces[:Null] = NullSpace.new

      User::init self
      @spaces[:Empty] = EmptySpace.new @monitor, :Empty, self
      @log.debug "Инициализация общей модели данных завершена"
    end

    def [] name = :Main
      # Мэйнстрим. Отрабатываем быстрее хэша.
      return self if name == :Main

      space = @spaces[name]
      # препятствуем удалению основного спейса из хэша, а также возврату спейса, если он не существует, т.к. если вместо этого
      # вернуть основной, его данные могут быть изменены логикой, которая должна работать на отдельном спейсе
      space && space.name == name ? space : nil
    end

    def get name
      @spaces.get name
    end

    # При доступе к спейсу методом [] он будет автоматически проинициализирован. Данный метод позволяет мониторить состояние
    # спейса не вызывая его автоматической загрузки. В настоящее время не используется.
    def loaded? name
      name == :Main || @spaces.has_key?(name)
    end

    def each
      @spaces.each { |name, space| yield name, space }
    end

    # Метод используется MasterProxyHash и методом load_data
    def _load_ name
      space_descriptor = @spaceAccount.get name
      return nil unless space_descriptor
      pattern_descriptor = @spacePatternAccount.get space_descriptor.pattern
      space = SubSpace.new @monitor, name, self, pattern_descriptor
      space.set_data_provider @data_provider
      space.set_concept_data_provider @concept_data_provider
      space.load_data
      @spaces[name] = space
      space
    end

    def delete space_name
      space = @spaces.delete space_name
      space.self_delete if space
    end

    def create_class_map
      @classes = Hash[
        :storageAccount 		=> StorageAccount,
        :classAccount 			=> ClassAccount,
        :objectAccount 			=> ObjectAccount,
        :propertyAccount 		=> PropertyAccount,
        :spacePatternAccount  	=> SpacePatternAccount,
        :spaceAccount         	=> SpaceAccount,
        :topologyAccount      	=> TopologyAccount,
        :moduleAccount        	=> ModuleAccount,
        :modelAccount         	=> ModelAccount,
        :workflowAccount      	=> WFAccount,
        :guiAccount           	=> GUIAccount,
        :userGroupAccount     	=> UserGroupAccount,
        :userAccount          	=> UserAccount,
        :binaryAccount        	=> BinaryAccount,
        :settingsAccount        => SettingsAccount,
        :jobsAccount => JobsAccount,
        :messagePatternAccount	=> MessagePatternAccount,
        :messageAccount       	=> MessageAccount,
        :accessRightAccount   	=> AccessRightAccount,
        :roleAccount          	=> RoleAccount,
        :pluginAccount          => PluginAccount,
        :ustorageAccount        => UStorageAccount,
        :uobjectAccount         => UObjectAccount,
        :reportAccount          => ReportsAccount,
        :nullAccount            => NullAccount
      ]
    end

    def create_accounts
      super
      create_account :spacePatternAccount, 'Реестр шаблонов пространств данных'
      create_account :spaceAccount, 'Пространства данных'
      create_account :topologyAccount, 'Учёт узлов топологии'
      create_account :moduleAccount, 'Реестр модулей системы'
      create_account :modelAccount, 'Реестр моделей'
      create_account :workflowAccount, 'Реестр алгоритмов, процессов, приложений...'
      create_account :guiAccount, 'Реестр пользовательских интерфейсов'
      create_account :userGroupAccount, 'Реестр групп пользователей'
      create_account :userAccount, 'Реестр пользователей'
      create_account :binaryAccount, 'Реестр файлов'
      create_account :settingsAccount, 'Настройка'
      create_account :jobsAccount, 'Задачи'
      create_account :messagePatternAccount, 'Реестр шаблонов сообщений'
      create_account :messageAccount, 'Сообщения системы'
      create_account :accessRightAccount, 'Реестр прав доступа'
      create_account :roleAccount, 'Реестр ролей'
      create_account :pluginAccount, 'Плагины узла топологии'
      create_account :ustorageAccount, 'Реестр универсальных хранилищ'
      create_account :uobjectAccount, 'Загрузчик универсальных объектов', @ustorageAccount
      create_account :reportAccount, 'Реестр отчетов'
      create_account :nullAccount, 'dev/null'
    end

    def set_data_provider data_provider
      super data_provider
      @spaces.each_value do |space|
        next if space == self
        space.set_data_provider data_provider
      end
    end

    def load_users
      Time.measure 'load_users' do
        @accessRightAccount.load
        @roleAccount.load
        @userGroupAccount.load
        @userAccount.load
      end
    end

    def load_libraries
      Time.measure 'load_libraries' do
        @pluginAccount.load
      end
    end

    def load_definitions
      @log.debug 'Загрузка определений...'

      Time.measure 'load_spaces' do
        @spacePatternAccount.load
        @spaceAccount.load
      end

      Time.measure 'load_modules' do
        @moduleAccount.load
        @moduleAccount.build
      end

      # Storage теперь использует модули, при этом
      # должна грузиться и билдиться перед объектами !!!
      Time.measure 'load_storages' do
        @storageAccount.load
        @storageAccount.build
      end

      Time.measure 'load_classes' do
        @classAccount.load
        @classAccount.build
      end

      Time.measure 'load_models' do
        @modelAccount.load
        @modelAccount.build
      end

      Time.measure 'load_ustorages' do
        @ustorageAccount.load
        @ustorageAccount.build
      end

      Time.measure 'load_workflow' do
        @workflowAccount.load
      end

      Time.measure 'load_plugins' do
        # инициализируем кросс-классы
        @pluginAccount.initialize_classes
      end

      # Должен загружаться после StorageAccount, т.к. в ReplicationDescr.marshal_load используется обращение к StorageAccount
      Time.measure 'load_topology' do
        @topologyAccount.load
      end

      Time.measure 'load_reports' do
        @reportAccount.load
      end

      @log.debug 'Завершено: загрузка определений'
    end

    def load_data models_list = nil
      @log.debug 'Загрузка данных ...'

      Time.measure 'load_guis' do
        @guiAccount.load
        @guiAccount.build
      end

=begin
      Time.measure "load_topology" do
        @topologyAccount.load
      end
=end

      Time.measure 'load_binaries' do
        @binaryAccount.load
      end
      Time.measure 'load_settings' do
        @settingsAccount.load
      end
      Time.measure 'load_jobs' do
        @jobsAccount.load
      end
      Time.measure 'load_messages' do
        @messagePatternAccount.load
        @messageAccount.load
      end

      Time.measure 'load_objects' do
        # Загрузка объектов
        super models_list
      end

      Time.measure 'init_spaces' do
        # Загрузка пространств данных, которые должны быть загружены при старте сервера\приложения
        @spaceAccount.spaces.each do |name, space_descriptor|
          pattern_descriptor = @spacePatternAccount.get space_descriptor.pattern
          _load_ name if pattern_descriptor.download
        end
      end
      saving_ntfs_from_persistence_queue
      @log.debug "[#{self.class}] Завершено: загрузка данных"
    end

    def saving_ntfs_from_persistence_queue
      return if $_master_data_provider.nil? || !$_master_data_provider.respond_to?(:get_queue)
      $control.zookeeper_set_property(ZooKeeperClient::PROPERTY_STATE, ZooKeeperClient::STATUS_SYNCHRONIZE)
      $control.dtree.this_node.состояние.value = JGroupsModel::STATUS_SYNCHRONIZE if $control.dtree
      q = $_master_data_provider.get_queue
      Time.measure 'Loading NTFs from master' do
        while true
          elem = q.deq
          break if elem == :end
          ntf = elem[1]
          begin
            @log.debug "Processing event from DB: #{ntf.inspect}" if $control.arguments[:debug_ntf]
            $space[ntf.space].accounts[ntf.handler].handle ntf
          rescue Exception => err
            begin
              msg = 'Error while processing ntf'
              msg << "\nDebugging: processing NTF: #{ntf.inspect}"
              msg << "\nAction:#{ntf.action}" if ntf.respond_to? :action
              msg << "\nSpace:#{ntf.space}" if ntf.respond_to? :space
              msg << "\nObjId:#{ntf.obj_id}" if ntf.respond_to? :obj_id
              msg << "\nStrgId:#{ntf.strg_id}" if ntf.respond_to? :strg_id
              msg << "\nNewStrgId:#{ntf.new_strg_id}" if ntf.respond_to? :new_strg_id
              msg << "\nClassName:#{ntf.class_name}" if ntf.respond_to? :class_name
              msg << "\nNewClassName:#{ntf.new_class_name}" if ntf.respond_to? :new_class_name
              msg << "NewStrgId:#{ntf.new_strg_id}" if ntf.respond_to? :new_strg_id
              msg << "ClassName:#{ntf.class_name}" if ntf.respond_to? :class_name
              msg << "NewClassName:#{ntf.new_class_name}" if ntf.respond_to? :new_class_name
              msg << '==================='
              @log.warn msg, err
            rescue Exception => err2
              @log.info 'Error while printing ntf handling error', err2
            end
          end
        end
        @log.info('control.flush_in_queue')
        $control.flush_in_queue
        sleep(1)
        @log.info('Marking master queue table free')
        $_master_data_provider.release_queue
        @log.info 'Восстановление через очередь нотификаций завершено'
      end
    end

    def self_delete
      # Блокируем метод суперкласса. Основной спейс не разбирается и умирает только вместе с сервером
      raise 'Ошибка логики приложения или сервера - попытка уничтожения основного пространства данных'
    end

    # Не обязателен т.к. основные аккаунты не реализуют методы отката изменений.
    def rollback
      # Блокируем метод суперкласса. Основной спейс не может быть очищен от данных средствами приложения
      raise 'Ошибка логики приложения или сервера - попытка отката изменений основного пространства данных'
    end

    # Не обязателен т.к. основные аккаунты не реализуют методы фиксации данных.
    def commit
      # Блокируем метод суперкласса. Основной спейс может быть зафиксирован, в т.ч. и средствами приложения,
      # однако это действие для него не имеет смысла и, скорее всего, является ошибкой логики приложения.
      raise 'Ошибка логики приложения или сервера - попытка фиксации изменений основного пространства данных'
    end

    def get_nodes
      @topologyAccount.get_nodes_for_loading
    end

    def get_modules_defs
      @moduleAccount.module_defs
    end

    def get_classes_defs
      @classAccount.class_defs
    end

    def get_storages
      @storageAccount.storage_defs
    end

    def get_ustorages
      @ustorageAccount.storage_defs
    end

    def get_model_defs
      @modelAccount.model_defs
    end

    def get_wfs
      @workflowAccount.wf_defs
    end

    def get_guis
      @guiAccount.gui_defs
    end

    def get_users
      @userAccount.users
    end

    def get_user_groups
      @userGroupAccount.groups
    end

    def get_access_rights
      @accessRightAccount.rights
    end

    def get_roles
      @roleAccount.roles
    end

    def get_binaries
      @binaryAccount.binaries
    end

    def get_binary_data bin_id
      @binaryAccount.get_bytes bin_id
    end

    def get_settings
      @settingsAccount.settings
    end

    def get_jobs
      @jobsAccount.jobs
    end

    def get_message_patterns
      @messagePatternAccount.pattern
    end

    def get_messages
      msg_hash = {}
      @messageAccount.select(nil, nil, nil).each do |msg|
        msg_hash[msg.msg_id] = msg
      end
      msg_hash
    end

    def get_space_patterns
      @spacePatternAccount.pattern
    end

    def get_spaces
      @spaceAccount.spaces
    end

    def get_plugins
      @pluginAccount.plugins
    end

    def get_reports
      @reportAccount.report_defs
    end
  end
end