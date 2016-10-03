include Java

import org.jruby.RubyModule
import org.jruby.RubyBasicObject
import org.jruby.util.IdUtil

require 'iconv'

require File.dirname(__FILE__) + '/../commons/dsl_parser'
require File.dirname(__FILE__) + '/../gui/dsl/class_registry'


module User

  # Небольшой хак для использования protected методов класса
  class RubyModuleUtil < RubyModule

    def self.remove_const ruby_name, ruby_module
      raise "Wrong constant name #{ruby_name}" unless IdUtil.isConstant ruby_name
      return nil unless RubyModuleUtil.get_const ruby_name, ruby_module, false
      ruby_module.send(:remove_const, ruby_name.to_s)
    end

    def self.get_const ruby_name, ruby_module, inherit = true
      java_module = ruby_module.to_java
      # в случае отсутствия константы в кэше метод выбрасывает исключение, поэтому перехватываем...
      java_module.getConstant ruby_name.to_s, inherit rescue nil
    end

    # Следующие методы сохраняют в значениях атрибутов RubyObject объекты Java, а не объекты RubyObject...
    # к примеру java.lang.String вместо RubyString, что в последствии приводит к ошибкам в ядре JRuby

    #def self.instance_variable_get object, name
    #	value = object.to_java.variableTableFetch name.to_java.toString
    #	# Не очень понятно, какой именно объект может быть возвращен вместо nil
    #	return value ? value : nil
    #end
    #
    #def self.instance_variable_set object, name, value
    #	java_object = object.to_java
    #	java_object.ensureInstanceVariablesSettable
    #	java_object.getMetaClass.to_java.getRealClass.to_java.getVariableAccessorForWrite(name.to_java.toString).set java_object, value
    #	value
    #end
    #
    #def self.remove_instance_variable object, name
    #	java_object = object.to_java
    #	java_object.ensureInstanceVariablesSettable
    #	value = java_object.variableTableRemove name.to_java.toString
    #	return value if value
    #	raise NameError.new "instance variable " + name.to_java.toString + " not defined", name.to_java.toString
    #end
  end

  class BaseDsl

    def initialize name, is_new
      @name = name
      @new_object = is_new
      if @new_object
        @subsystems = Array.new
        @descr = ''
      else
        @dh_inserted = Hash.new
        @dh_removed = Hash.new
        @dh_classified = Hash[:inserted => @dh_inserted, :removed => @dh_removed]
      end
    end

    def belongs_to *subs
      @subsystems ||= []
      subs.each do |subsystem|
        raise 'Ошибка формата команды belongs_to: имя должно быть задано и иметь тип Symbol' unless subsystem.is_a? Symbol
        unless @subsystems.include? subsystem
          @subsystems << subsystem
          unless @new_object
            @dh_inserted[:subsystems] ||= []
            @dh_inserted[:subsystems] << subsystem
          end
        end
      end
    end
    alias :'подсистемы' :belongs_to

    def exclude_from *subs
      raise 'Команда exclude_from не может быть выполнена при создании.' if @new_object
      @subsystems ||= []
      subs.each do |subsystem|
        raise 'Ошибка формата команды exclude_from: имя должно быть задано и иметь тип Symbol' unless subsystem.is_a? Symbol
        if @subsystems.delete subsystem
          @dh_removed[:subsystems] ||= []
          @dh_removed[:subsystems] << subsystem
        end
      end
    end

    def исключить params
    what, subs = params
    if what == :subsystem
      exclude_from *subs
    else
      raise 'Ошибка формата команды: исключить подсистему :"Название подсистемы"'
    end
    end

    def подсистему *subs
    [:subsystem, subs]
    end

    def get_subsystems
      @subsystems
    end

    def description descr
      descr = "#{descr}"
      unless @new_object
        if @descr
          if descr
            # замену одного на другое считаем вставкой
            @dh_inserted[:descr] = descr if @descr != descr
          else
            # было и теперь не будет - чистое удаление
            @dh_removed[:descr] = descr
          end
        else
          # не было и теперь будет - чистая вставка
          @dh_inserted[:descr] = descr
        end
      end
      @descr = descr
    end
    alias описание description

    def get_description
      @descr
    end
  end

end

require File.dirname(__FILE__) + '/models'
require File.dirname(__FILE__) + '/storage'
require File.dirname(__FILE__) + '/ustorage'
require File.dirname(__FILE__) + '/report'
require File.dirname(__FILE__) + '/objects'
require File.dirname(__FILE__) + '/classes'
require File.dirname(__FILE__) + '/modules'
require File.dirname(__FILE__) + '/dsl_wf'
require File.dirname(__FILE__) + '/attributes'
require File.dirname(__FILE__) + '/topology'
require File.dirname(__FILE__) + '/interfaces'
require File.dirname(__FILE__) + '/geometry'
require File.dirname(__FILE__) + '/user'
require File.dirname(__FILE__) + '/../entity_access_rights'
require File.dirname(__FILE__) + '/../entity_roles'
require File.dirname(__FILE__) + '/../entity_plugins'
require File.dirname(__FILE__) + '/../entity_storages'
require File.dirname(__FILE__) + '/../entity_ustorages'
require File.dirname(__FILE__) + '/../entity_reports'
require File.dirname(__FILE__) + '/binary'
require File.dirname(__FILE__) + '/settings'
require File.dirname(__FILE__) + '/jobs'
require File.dirname(__FILE__) + '/message'
require File.dirname(__FILE__) + '/spaces'

module User

  #noinspection RubyDeadCode
  class Dsl
    #@@parsing_mode = true
    #@@parsing_mode = false unless defined? @@parsing_mode
    # семантика DO/END пока только при запуске нового дизайнера
    @@ruby_block_syntax = NBStarter.ruby_block_syntax? unless defined? @@ruby_block_syntax

    #def self.enable_parsing enable=true
    #	@@ruby_block_syntax = enable
    #end

    def self.in_parsing_mode?
      @@ruby_block_syntax
    end

    def self.get_text_block name
      return nil unless User::Dsl.in_parsing_mode?
      dsl_parser = Thread.current[:dsl_parser]
      #puts dsl_parser
      return nil unless dsl_parser
      text = dsl_parser.get_fcall(name)
      text = text.gsub("\r\n","\n") if text
      text
    end

    def exec dsl, filename = nil, lineno = nil
      begin

        dsl_parser = DslParser.new(dsl)
        dsl_parser.set_line_offset(1)
        Thread.current[:dsl_parser] = dsl_parser

        if User::Users.has_role? Role::SCRIPT_EXECUTION_ROLE_NAME
          script = " lambda {\n#{dsl}\n}.call() "
          if filename
            if lineno
              self.instance_eval(script, filename, lineno)
            else
              self.instance_eval(script, filename)
            end
          else
            self.instance_eval(script)
          end
        else
          puts "У текущего пользователя '#{User::Users.current_user_name}' отсутствуют права на исполнение скриптов"
        end
      rescue SyntaxError => err
        puts "Синтаксическая ошибка в выражении: #{LogUtil.trace err}"
        raise err
      ensure
        Thread.current[:dsl_parser] = nil
      end
    end

    def self.run &block
      if User::Users.has_role? Role::SCRIPT_EXECUTION_ROLE_NAME
        Dsl.new.instance_eval &block
      else
        puts "У текущего пользователя '#{User::Users.current_user_name}' отсутствуют права на исполнение скриптов"
      end
    end

    def self.run_script dsl
      # Убираем BOM из заголовка скрипта в кодировке UTF-8 with BOM
      dsl = dsl.sub("\xEF\xBB\xBF", '')
      result = ScriptResult.new
      Thread.new result do |callback|
        begin
          Thread.current.name = "run script #{dsl[0..20]}"
          result.value = Dsl.new.exec dsl
        rescue Exception => ex
          result.value = ex
        end
      end.join
      if result.value.kind_of? Exception
        raise result.value
      else
        result.value
      end
    end

    def self.run_file path
      dsl = File.read(path, :encoding => 'bom|utf-8')
      result = ScriptResult.new
      Thread.new result do |callback|
        begin
          Thread.current.name = "run file #{path}"
          result.value = Dsl.new.exec dsl
        rescue Exception => ex
          result.value = ex
        end
      end.join
      if result.value.kind_of? Exception
        raise result.value
      else
        result.value
      end
    end

    class ScriptResult
      attr_accessor :value
    end

    def self.format_dsl_block block_text, prefix

      return StringUtil.to_dsl(block_text,prefix) unless User::Dsl.in_parsing_mode?
      #return "do\n#{block_text}\n#{prefix}end"

      dsl = 'do'
      lines = []
      block_text.each_line do |line|
        c = line.chars.to_a[line.size-1]
        line = line.tr("\r\n", '')
        lines << line
      end
      dsl << "\n" if lines.size > 0 && ! lines[0].tr(" \t", '').empty?
      dsl << block_text
      dsl << "\n" if lines.size > 0 && ! lines[lines.size-1].tr(" \t", '').empty?
      dsl << "#{prefix}end"
      dsl
    end


    def Объект obj_id = nil, space = :Main
    raise "В инструкции 'Объект' не указан идентификатор объекта" unless obj_id
    UserObject.get obj_id, space
    end

    def отправить instruction, &block
    what, message = instruction
    case what
      when :message
        if message.is_a? User::Message
          message.dispatch
        else
          User::Message.send &block
        end
      else
        puts "Для сущности '#{what.to_s}' операция 'отправить' не определена."
    end
    end

    def обновить instruction, &block
    what, name = instruction
    case what
      when :subsystem
        Subsystem.recreate name, &block
      when :module
        Module.recreate name, &block
      when :class
        UserClass.recreate name, &block
      when :storage
        Storage.recreate name, &block
      when :object
        puts "Инструкция 'обновить' не определена для объектов"
      when :data_model
        Model.recreate name, &block
      when :state_mashine
        StateMashine.recreate name, &block
      when :domain
        Domain.recreate name, &block
      when :event
        Event.recreate name, &block
      when :techprocess
        puts "Инструкция 'обновить' не определена для техпроцессов"
      #RunningProcess.recreate name, &block
      when :techprocess_pattern
        Process.recreate name, &block
      when :scene
        JRScene.recreate name[0], name[1], &block
      when :geo_layer
        GeoScene.recreate name, &block
      when :geo_sign
        GeoSign.recreate name, &block
      when :application
        Application.recreate name, &block
      when :host
        Host.recreate name, &block
      when :app_server
        ApplicationServer.recreate name, &block
      when :db
        Database.recreate name, &block
      when :broker
        Broker.recreate instruction[2], name, &block
      when :replication
        Replication.recreate name, &block
      when :db_cluster
        DbCluster.recreate name, &block
      when :ext_service_cluster
        ExtServiceCluster.recreate instruction[2], name, &block
      when :reserve_cluster
        ReserveCluster.recreate name, &block
      when :admin_cluster
        AdminCluster.recreate instruction[2], name, &block
      when :user
        puts "Инструкция 'обновить' не определена для пользователей"
      when :document
        puts "Инструкция 'обновить' не определена для документов"
      when :message
        puts "Инструкция 'обновить' не определена для сообщений"
      when :message_pattern
        MessagePattern.recreate &block
      when :space
        # todo: С использованием GUIUtil выдать диалог подтверждения операции с предупреждением об удалении данных
        Space.recreate &block
      when :space_pattern
        SpacePattern.recreate &block
      when :user_group
        UserGroup.recreate name, &block
      when :access_right
        AccessRight.recreate name, &block
      when :role
        Role.recreate name, &block
      when :plugin
        Plugin.recreate name, &block
      else
        puts "Сущность '#{what.to_s}' не определена в системе"
    end
    end

    def создать instruction, &block
    what, name = instruction
    case what
      when :subsystem
        Subsystem.create name, &block
      when :module
        Module.create name, &block
      when :class
        UserClass.create name, &block
      when :storage
        Storage.create name, &block
      when :object
        UserObject.create name[0], &block
      when :data_model
        Model.create name, &block
      when :state_mashine
        StateMashine.create name, &block
      when :domain
        Domain.create name, &block
      when :event
        Event.create name, &block
      when :techprocess
        Process.set_ready name
      when :techprocess_pattern
        Process.create name, &block
      when :scene
        JRScene.create name[0], name[1], &block
      when :geo_layer
        GeoScene.create name, &block
      when :geo_sign
        GeoSign.create name, &block
      when :application
        Application.create name, &block
      when :host
        Host.create name, &block
      when :app_server
        ApplicationServer.create name, &block
      when :db
        Database.create name, &block
      when :broker
        Broker.create instruction[2], name, &block
      when :replication
        Replication.create name, &block
      when :db_cluster
        DbCluster.create name, &block
      when :ext_service_cluster
        ExtServiceCluster.create instruction[2], name, &block
      when :reserve_cluster
        ReserveCluster.create name, &block
      when :admin_cluster
        AdminCluster.create instruction[2], name, &block
      when :user
        Users.create &block
      when :document
        Binary.create &block
      when :message
        Message.create &block
      when :message_pattern
        MessagePattern.create &block
      when :space
        Space.create &block
      when :space_pattern
        SpacePattern.create &block
      when :user_group
        UserGroup.create name, &block
      when :access_right
        AccessRight.create name, &block
      when :role
        Role.create name, &block
      when :plugin
        Plugin.create name, &block
      when :settings
        Settings.create(&block)
      else
        puts "Сущность '#{what.to_s}' не определена в системе"
    end
    end

    def удалить instruction
    what, name = instruction
    case what
      when :subsystem
        Subsystem.delete name
      when :module
        Module.delete name
      when :class
        UserClass.delete name
      when :storage
        # Здесь name - строка
        Storage.delete name
      when :object
        if name[0].class == UserObject
          UserObject.del_object name[0]
        else
          # здесь name - идентификатор объекта UserObject.obj_id плюс UserObject.space
          UserObject.del_object_by_id name[0], name[1]
        end
      when :data_model
        Model.delete name
      when :state_mashine
        StateMashine.delete name
      when :domain
        Domain.delete name
      when :event
        Event.delete name
      when :techprocess
        RunningProcess.delete name[0]
      when :techprocess_pattern
        Process.delete name
      when :scene
        JRScene.delete name[0]
      when :geo_layer
        GeoScene.delete name
      when :geo_sign
        GeoSign.delete name
      when :application
        Application.delete name
      when :host
        Host.delete name
      when :app_server
        ApplicationServer.delete name
      when :db
        Database.delete name
      when :broker
        Broker.delete name
      when :replication
        Replication.delete name
      when :db_cluster
        DbCluster.delete name
      when :ext_service_cluster
        ExtServiceCluster.delete name
      when :reserve_cluster
        ReserveCluster.delete name
      when :admin_cluster
        AdminCluster.delete name
      when :user
        Users.delete name
      when :document
        Binary.delete name
      when :settings
        Settings.delete(name)
      when :message
        Message.delete name
      when :message_pattern
        MessagePattern.delete name
      when :space
        Space.delete name
      when :space_pattern
        SpacePattern.delete name
      when :user_group
        UserGroup.delete name
      when :access_right
        AccessRight.delete name
      when :role
        Role.delete name
      when :plugin
        Plugin.delete name
      else
        puts "Сущность '#{what.to_s}' не определена в системе"
    end
    end

    def изменить instruction, &block
    what, name = instruction
    case what
      when :subsystem
        Subsystem.modify name, &block
      when :module
        Module.modify name, &block
      when :class
        UserClass.modify name, &block
      when :storage
        # Здесь name - строка
        Storage.modify name, &block
      when :object
        # здесь name - идентификатор объекта UserObject.obj_id, а так же идентификатор пространства данных UserObject.space
        UserObject.modify name[0], name[1], &block
      when :data_model
        Model.modify name, &block
      when :state_mashine
        StateMashine.modify name, &block
      when :domain
        Domain.modify name, &block
      when :event
        Event.modify name, &block
      when :techprocess
        puts "Инструкция 'изменить' не определена для техпроцессов"
      when :techprocess_pattern
        Process.modify name, &block
      when :scene
        puts "Инструкция 'изменить' не определена для сцен"
      when :geo_layer
        GeoScene.modify name, &block
      when :geo_sign
        puts "Инструкция 'изменить' не определена для знаков символизации"
      when :application
        Application.modify name, &block
      when :host
        Host.modify name, &block
      when :app_server
        ApplicationServer.modify name, &block
      when :db
        Database.modify name, &block
      when :broker
        Broker.modify name, &block
      when :replication
        Replication.modify name, &block
      when :db_cluster
        DbCluster.modify name, &block
      when :ext_service_cluster
        ExtServiceCluster.modify name, &block
      when :reserve_cluster
        ReserveCluster.modify name, &block
      when :admin_cluster
        AdminCluster.modify name, &block
      when :user
        Users.modify name, &block
      when :document
        Binary.modify name, &block
      when :settings
        Settings.modify(name, &block)
      when :message
        Message.modify name, &block
      when :message_pattern
        MessagePattern.modify name, &block
      when :space
        Space.modify name, &block
      when :space_pattern
        SpacePattern.modify name, &block
      when :user_group
        UserGroup.modify name, &block
      when :access_right
        AccessRight.modify name, &block
      when :role
        Role.modify name, &block
      when :plugin
        Plugin.modify name, &block
      else
        puts "Сущность '#{what.to_s}' не определена в системе"
    end
    end

    def пауза seconds
    sleep seconds
    end

    def понятие name
    [:module, name]
    end

    def прототип name
    [:class, name]
    end

    def репозиторий name
    [:storage, name]
    end

    def подсистему name
    [:subsystem, name]
    end

    # @param obj_id_or_object_or_space [Fixnum|UserObject|Symbol] - при создании - имя спейса, при удалении объект или
    #         идентификатор объекта, при модификации - идентификатор объекта.
    def объект obj_id_or_object_or_space = :Main, space = :Main
    [:object, [obj_id_or_object_or_space, space]]
    end

    def данных name = nil
    [:data_model, name]
    end

    def модель instruction
    instruction
    end

    def состояний name
    [:state_mashine, name]
    end

    def домен name
    [:domain, name]
    end

    def событие name
    [:event, name]
    end

    def техпроцесс pattern, name = nil, params = nil
    [:techprocess, [pattern, name, params]]
    end

    def техпроцесса name
    [:techprocess_pattern, name]
    end

    def пространства instruction
    # DLS: создать шаблон пространства данных принять
    # метод 'данных' возвращает [:data_model, name] - символ заменяем:
    instruction[0] = :space_pattern
    instruction
    end

    def пространство instruction
    # DLS: создать пространство данных принять
    # метод 'данных' возвращает [:data_model, name] - символ заменяем:
    instruction[0] = :space
    instruction
    end

    # для разных типов шаблонов
    def шаблон instruction
    instruction
    end

    # для разных типов знаков
    def знак instruction
    instruction
    end

    # для разных типов машин
    def машину instruction
    instruction
    end

    # для разных типов узлов
    def узел instruction
    instruction
    end

    def группу instruction
    instruction
    end

    # промежуточный дсл
    def право instruction
    instruction
    end

    def доступа name
    [:access_right, name]
    end

    def роль name
    [:role, name]
    end

    def плагин name
    [:plugin, name]
    end

    def сцену type, name = nil
    [:scene, [type, name]]
    end

    def примитивов name
    [:geo_layer, name]
    end

    def пользователей name
    [:user_group, name]
    end

    def символизации name
    [:geo_sign, name]
    end

    def приложение name
    [:application, name]
    end

    def сервер name = nil
    [:host, name]
    end

    def сервер_приложений name = nil
    [:app_server, name]
    end

    def база_данных name = nil
    [:db, name]
    end
    alias базу_данных база_данных

    def брокер service_type = nil, name = nil
    # Иногода имя идёт 1-ым параметром
    name = service_type unless name
    [:broker, name, service_type]
    end
    alias брокера брокер

    def репликация name = nil
    [:replication, name]
    end
    alias репликацию репликация

    def кластер_баз_данных name = nil
    [:db_cluster, name]
    end

    def кластер_внешних_сервисов service_type = nil, name = nil
    # Иногода имя идёт 1-ым параметром
    name = service_type unless name
    [:ext_service_cluster, name, service_type]
    end

    def кластер_резервирования name = nil
    [:reserve_cluster, name]
    end

    def кластер_администрирования service_type = nil, name = nil
    # Иногода имя идёт 1-ым параметром
    name = service_type unless name
    [:admin_cluster, name, service_type]
    end

    def пользователя name = nil
    [:user, name]
    end

    def документ name = nil
    [:document, name]
    end

    # При отправке ранее созданного экземпляра, в метод передается экземпляр сообщения
    def сообщение name = nil
    [:message, name]
    end

    def сообщения name = nil
    [:message_pattern, name]
    end

    def help *params
      puts 'help command'
      puts ClassRegistry.help params
    end

  end

  # alias
  class DSL < Dsl

    def self.инструкция &block
    Dsl.run &block
    end
  end

  class Script

    def initialize
      @path = '.'
    end

    def self.execute &block
      engine = Script.new
      engine.instance_eval &block if block_given?
    end

    def path path
      @path = path if path
      @path << '/'
    end

    def run file_name
      path = @path ? @path + file_name : file_name
      begin
        file = File.open path, 'r'
        content = file.read
        instance_eval content
      rescue Exception => err
        puts "Ошибка выполнения скрипта #{path}: #{LogUtil.trace err}"
      ensure
        file.close if file
      end
    end
  end
end