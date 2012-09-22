class Settings < ActiveRecord::Base
  include ::PersistentSettings
  @mutex = Mutex.new

  serialize :value

  def self.method_missing(method_name, *args)
    if assignation?(method_name)
      self.define_setter_and_getter(method_name)
      self.send(method_name, args.first)
    else
      super
    end
  end

  def self.define_setter_and_getter(method_name)
    getter = method_name.to_s.chop

    (class << self; self; end).instance_eval do
      define_method method_name do |value|
        @mutex.synchronize do
          persist(getter, value)
          write_to_cache getter, value
        end
      end

      define_method getter do
        value = read_from_cache getter
        unless value
          value = read_from_persistance getter
          write_to_cache getter, value
        end
        value
      end
    end
  end

  def self.assignation?(method_name)
    method_name.to_s.match(/=$/)
  end

  def self.persist(getter, value)
    setting = Settings.where(:var => getter).last
    if setting
      setting.update_attribute(:value, value)
    else
      Settings.create(:var => getter, :value => value)
    end
  end

  def self.load_from_persistance!
    self.all.each do |setting|
      self.send("#{setting.var}=", setting.value)
    end
  end

  def self.read_from_persistance(key)
    Settings.find_by_var(key).value
  end

  def self.load_from_persistance
    load_from_persistance! if ready?
  end

  def self.cache_key_for(key)
    "settings/#{key}"
  end

  def self.write_to_cache(key, value)
    ::Rails.cache.write(cache_key_for(key), value)
  end

  def self.read_from_cache(key)
    ::Rails.cache.fetch(cache_key_for(key))
  end

  def self.ready?
    connected? && table_exists?
  end

  def self.keys
    Settings.select(:var).collect { |s| s.var.to_sym }
  end

  load_from_persistance
end
