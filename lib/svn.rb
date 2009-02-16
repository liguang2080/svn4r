require "fileutils"

#svn.new("http://location")
#svn.local的支持方法:
#version add ci del update

#svn.remote的支持方法:
#version co

# Example
# #远程操作 remote,返回一个SvnRemote对象
# resp = Svn.ini("svn://localhost/test/trunk")
# puts "初始服务器版本" + resp.version.to_s
# 
# # checkout到某个目录,可带路径,default为RAILS_ROOT,返回一个SVNLocal对象
# local = resp.co("google")
# 
# puts "checkout 后本地版本" + local.version.to_s 
# 
# # 将文件增加进版本库
# local.add("/Users/lg2046/test.txt")
# local.ci
# 
# puts "文件增加后版本" + local.version.to_s 
# 
# File.open("/Users/lg2046/test.txt", "w"){ |f| f.puts "changed" + Time.now.to_s}
# 
# local.replace("/Users/lg2046/test.txt")
# local.ci
# 
# puts "文件修改后版本" + local.version.to_s
# 
# # 把文件删除掉
# local.del("test.txt")
# local.ci("delete file")
# 
# puts "文件删除后版本" + local.version.to_s
# 
# svnlocal = Svn.ini("/Users/lg2046/google")
# puts "最后本地Local" + svnlocal.version.to_s
# 
# svnlocal.remove_local

#对远程进行操作
#Svn.ini("svn://localhost/test/trunk").co("google").add("/Users/lg2046/test.txt").ci.remove_local

class Svn

  class NoAuthInfoError < StandardError
  end

  attr_accessor :path, :user, :pwd

  def initialize(path)
    @path = path
  end

  class << self
    def ini(path)
      path.starts_with?('http://') ? SvnRemote.new(path) : SvnLocal.new(path)
    end

    # 在调用方法前进行验证是否有用户名与密码
    def check_auth(*args)
      args.each do |method|
        class_eval <<-EOF
        alias :ori_#{method.to_s} #{method} 
        def #{method.to_s}(*args, &block)
          check_user_and_pwd
          ori_#{method.to_s}(*args,&block)
        end
        EOF
      end
    end
  end

  # 从XML文件中抽取出版本信息
  def extract_version(xml)
    infodoc = XmlSimple.xml_in(xml)
    infodoc["entry"][0]["commit"][0]["revision"].to_i
  end

  # 执行svn命令的唯一入口,可以指定操作的目录 do_cmd("svn update", :path => "c:\\")
  def do_cmd(cmd_str, options = {})
    options[:path] ||= RAILS_ROOT
    Dir.chdir(options[:path])
    `#{cmd_str}`
  end

  def check_user_and_pwd
    unless @user && @pwd
      info = ExternalSenseInfo.find_by_name("svn")
      raise NoAuthInfoError unless info
      @name ||= info.account
      @pwd ||= info.pass
    end
  end
end

class SvnRemote < Svn
  def version
    extract_version(do_cmd("svn info #{@path} --username #{@name} --password #{@pwd} --xml"))
  end

  #把版本checkout到什么目录,并返回一个新的本地SvnLocal对象
  def co(path = "")
    if File.directory?(path)
      Dir.chdir(path)
      path  = File.join(path, File.basename(@path)+Time.now.strftime("%Y_%m_%d_%H_%M_%S"))
    end
    do_cmd("svn co #{@path} --username #{@name} --password #{@pwd} #{path}")
    SvnLocal.new(File.expand_path(path))
  end

  check_auth :version, :co
end

class SvnLocal < Svn

  def version
    update
    extract_version(do_cmd("svn info --xml", :path => @path))
  end

  def update
    do_cmd("svn update --username #{@name} --password #{@pwd}", :path => @path)
    self
  end

  def add(file)
    FileUtils.cp(file,@path)
    do_cmd("svn add #{File.basename(file)}", :path => @path)
    self
  end

  def ci(message = "some log")
    do_cmd("svn commit -m \"#{message}\"", :path => @path)
    self
  end

  # 接受一个文件名
  def del(file)
    do_cmd("svn del #{file}", :path => @path)
    self
  end

  def replace(file)
    FileUtils.cp(file, @path)
    self
  end

  def remove_local
    Dir.chdir(RAILS_ROOT)
    FileUtils.rm_r(@path) if File.directory?(@path)
  end

  check_auth :update, :ci
end