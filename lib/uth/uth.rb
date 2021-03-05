require 'xcodeproj'
require 'pathname'

class UnitTestHelper
  # 构造器方法
  def initialize(project_dir, component_path_list)
    # 主工程路径
    @project_dir = project_dir

    # 组件路径列表
    @component_path_list = component_path_list

    # 组件的 test target
    @component_test_target_map = {}

    # 组件 test group 路径
    @component_test_group_map = {}

    # 组件对应的 xcodeproj
    @component_project_map = {}


    puts "project: #{project_dir}"
    puts "component: #{component_path_list}"

    open_main_xcodeproj()

    process_all_components()

  end

    # 找到.xcodeproj后缀文件，返回其路径
  def find_xcodeproj(proDir)
    if !File.exist?(proDir)
      puts "#{proDir} does not exist"
      return
    end

    path_name = Pathname.new(proDir)
    project_path = '' # xcodeproj文件路径

    path_name.children.collect do |child|
      if File.extname(child).end_with?('.xcodeproj')
        project_path = child.to_s
        break
      end
    end

    return project_path
  end

  # 打开工程
  def open_xcodeproj(project_path)

    xcodeproj_path = find_xcodeproj(project_path)
    
    if xcodeproj_path != nil and File.exist?(xcodeproj_path)
      project = Xcodeproj::Project.open(xcodeproj_path)
      return project
    else
      return nil
    end  end

  # 打开主工程
  def open_main_xcodeproj()

    @main_project = open_xcodeproj(@project_dir)
    if @main_project.nil?
      puts "main_project is nil"
      return
    end

    # 找到 test target
    @main_project.targets.each do |target|
        if target.test_target_type?
            @main_test_target = target
            @main_test_path = @project_dir + "/#{target.name}"
            break
        end
    end
  end

  # 处理所有组件
  def process_all_components()
    unless @component_path_list
        return
    end

    @component_path_list.each do |component_path|
        process_component(component_path)
    end
  end

  # 处理组件
  def process_component(component_path)
    unless component_path
        return
    end

    if (!File.exist?(component_path))
        puts "#{component_path} does not exits!"
        return
    end

    # 找到 tests target
    component_example_path = component_path + "/Example"
    component_project = open_xcodeproj(component_example_path)

    unless component_project
        return
    end

    # 获取组件名
    component_name = get_component_name(component_path)

    # 保存组件 project
    if !@component_project_map.include?(component_name)
        @component_project_map[component_name] = component_project
    end
 
    component_project.targets.each do |target|
        if target.test_target_type?
            component_test_group = component_example_path + "/#{target.name}"
            
            # 保存组件 test 文件夹路径
            if !@component_test_group_map.include?(component_name)
                @component_test_group_map[component_name] = component_test_group
            end

            # 保存组件 test target
            if !@component_test_target_map.include?(component_name)
                @component_test_target_map[component_name] = target
            end

            # 旧工程的文件夹是 Tests，重命名 test target 的名字，防止同步到主工程冲突
            if !File.exist?(component_test_group)

              old_component_test_group = component_example_path + "/Tests"

              if File.exist?(old_component_test_group)
                
                puts "rename #{old_component_test_group} to #{component_test_group}"

                # 重命名
                File.rename(old_component_test_group, component_test_group)

                old_tests_group = component_project["Tests"]
                rm_group_ref(old_tests_group)
            
                # 文件夹重命名后，修改 test target 中 build setting 的 GCC_PREFIX_HEADER 和 INFOPLIST_FILE 路径
                target.build_configurations.each do |config|
                  config.build_settings['GCC_PREFIX_HEADER'] = "#{target.name}/Tests-Prefix.pch"
                  config.build_settings['INFOPLIST_FILE'] = "#{target.name}/Tests-Info.plist"
                end
              end

               # 如果有 Tests.m 文件，也重命名
              old_component_test_file = File.join(component_test_group, 'Tests.m')

              component_test_file = File.join(component_test_group, "#{target.name}.m")

              if File.exist?(old_component_test_file) and !File.exist?(component_test_file)
                  puts "rename #{old_component_test_file} to #{component_test_file}"
                  File.rename(old_component_test_file, component_test_file)
              end

              # 改名后，添加引用
              sync_component_back(component_name)
            end

            break
        end
    end
  end

  # 改名后，更新引用
  def update_component(component_name)
  end

  def rm_all_test_group_ref()
    unless @main_project
      return
    end

    puts "\n======== begin clear main project env... ========\n"

    groups = @main_project["DYZBTests"].groups
    groups.each do |group|
      if group.name.end_with?("Tests")
        rm_test_group_ref(group.name)
      end
    end

    save_main()

    puts "\n======== clear main project env done... ========\n"
  end

  # 移除组件在主工程的 group 引用
  def rm_test_group_ref(component_target_name)
    unless component_target_name
        return
    end

    unless @main_project
      return
    end

    # 组件在主工程所在的 group
    component_test_group = @main_project["DYZBTests"][component_target_name]

    unless component_test_group
      return
    end

    puts "rm group ref:#{component_test_group}"

    # 删除 group 引用
    rm_group_ref(component_test_group)
  end

  # 删除 group 引用
  def rm_group_ref(group_ref)
    unless group_ref
        return
    end

    group_ref.groups.each do | group|
        # 递归删除
        rm_group_ref(group)

        # 移除引用
        group.remove_from_project
    end
    
    group_ref.files.each do | file|
        # 删除 build phase 中的文件
        @main_test_target.source_build_phase.remove_file_reference(file)

        # 移除引用
        file.remove_from_project
    end
    
    # 移除引用
    group_ref.remove_from_project
  end

  # 添加组件测试用例文件引用到主工程 test target
  def add_file_ref(dir, current_group, target)
    unless  dir and target and current_group
        puts "add_file_ref params error!"
        return
    end

    Dir.glob(dir) do |item|
        next if item == '.' or item == '.DS_Store'

        if File.directory?(item)
            new_folder = File.basename(item)

            # 创建 group
            created_group = current_group.new_group(new_folder)

            # 设置实际路径
            created_group.set_path(item)

            add_file_ref("#{item}/*", created_group, target)
        else 
            # if item.end_with? ".m"
                ref = current_group.new_reference(item)
                target.add_file_references([ref])
            # end
        end
    end
  end

  # 同步所有组件 test 文件到主工程
  def sync_all_components_to_main()
    unless @component_path_list and @component_path_list.length > 0
        return
    end

    @component_path_list.each do |component_path|
        component_name = get_component_name(component_path)
        sync_component_to_main(component_name)
    end
  end

  # 同步组件用例文件到主工程
  def sync_component_to_main(component_name)
    unless component_name
      return
    end

    unless @main_project
      puts "main_project is nil"
      return
    end

    component_test_target = @component_test_target_map[component_name]
    unless component_test_target
        puts "#{component_name} target is nil"
        return
    end

    component_test_group_path = @component_test_group_map[component_name]
    unless component_test_group_path
        puts "#{component_name} test group path is nil"
        return
    end

    puts "\n======== begin sync #{component_name} unit tests to main... ========\n"

    main_test_group = @main_project.main_group.find_subpath("DYZBTests", true)  

    # 将组件的 Tests 文件下的用例文件，添加引用到主工程 test_group
    # 先移除存在的 group ref
    rm_test_group_ref(component_test_target.name)

    # tests 文件下的文件，添加引用到主工程
    add_file_ref(component_test_group_path, main_test_group, @main_test_target)

    # 保存工程文件
    save_main()

    puts "\n======== sync #{component_name} unit tests to main done... ========\n"
  end

  # 写回所有组件
  def sync_all_components_back()
    unless @component_path_list
        return
    end

    @component_path_list.each do |component_path|
        component_name = get_component_name(component_path)
        sync_component_back(component_name)
    end
  end

  # 在组件中，同步组件用例文件引用
  def sync_component_back(component_name)
    unless component_name
        return
    end

    puts "\n========  sync #{component_name} unit tests  back... ========\n"

    # 将组件 xxTests 文件下的文件添加引用
    component_test_target = @component_test_target_map[component_name]
    unless component_test_target
        puts "#{component_name} target is nil"
        return
    end

    component_test_group_path = @component_test_group_map[component_name]
    unless component_test_group_path
        puts "#{component_name} test group path is nil"
        return
    end
    
    component_project = @component_project_map[component_name]
    unless component_project
        puts "#{component_name} project is nil"
        return
    end

    # 移除组件的 test group
    orig_component_test_group = component_project[component_test_target.name]
    if (!orig_component_test_group.nil?) 
        puts "remove orig_component_test_group #{orig_component_test_group}"
        orig_component_test_group.remove_from_project
    end

    # 组件的 test group
    component_test_group = component_project.main_group

    # 重新添加组件单测文件引用
    add_file_ref(component_test_group_path, component_test_group, component_test_target)

    component_project.save()

    puts "\n======== sync #{component_name} unit tests back done... ========\n"
  end

  # 根据路径获取组件名
  def get_component_name(component_path)
    unless component_path
        return nil
    end

     # 获取组件名
    if component_path.end_with?('/')
        component_path = component_path.slice(0, component_path.length - 1)
    end

    list = component_path.split("/")
    component_name = list[list.length - 1]

    return component_name
  end

  # 清理环境
def clear()
   rm_all_test_group_ref()
end

  # 保存
  def save_main()
    unless @main_project
        return
    end

    @main_project.save()
  end
end
