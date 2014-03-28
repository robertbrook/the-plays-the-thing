BASE_DIR = ENV["PTT_HOME"] || File.join(File.dirname(__FILE__), "..")

def relative_path(filename)
  return "#{BASE_DIR}/#{filename}"
end

SRC_FOLDER = relative_path("src/preprocessed")
DEST_FOLDER = relative_path("public")

require 'rexml/document'
require 'erubis'

class PlayParser

  def initialize(collector)
    @out = collector
  end

  def optional_scene(root, name)
    scene = root.elements.to_a(name).first
    if scene
      yield 
      scene(scene)
    end
  end

  def scan(doc)
    doc.elements.each('PLAY/TITLE') do |t|
      @out.play_title t.text
    end 
    doc.elements.each('PLAY/PLAYSUBT') do |t|
      @out.play_subtitle t.text 
    end 
    if (doc.elements.to_a("PLAY/INDUCT/SCENE").length > 0)
      acts(doc, 'PLAY/INDUCT')
    else
      optional_scene(doc,'PLAY/INDUCT') { @out.start_induct }
    end
    optional_scene(doc,'PLAY/PROLOGUE') { @out.start_prologue }
    acts(doc,'PLAY/ACT')
    optional_scene(doc, 'PLAY/EPILOGUE') { @out.start_epilogue }
  end

  def acts(doc,pattern)
    doc.elements.each(pattern) do |a|
      @out.start_act
      a.elements.each('TITLE') do |t|
        @out.act_title t.text
      end
      optional_scene(a,'PROLOGUE') { @out.start_act_prologue }
      scenes(a,'SCENE') 
      optional_scene(a,'EPILOGUE') { @out.start_act_epilogue }
    end
  end

  def scenes(doc,elem)
    doc.elements.each(elem) do |s|
      @out.start_scene
      scene(s) 
    end
  end

  def scene(s) 
      return unless s
      s.elements.each('TITLE') do |t|
        @out.scene_title t.text
      end
      s.elements.each do |l|
        case l.name
          when 'SPEECH'
            speech(l)
          when 'STAGEDIR','SUBHEAD'
            @out.scene_stagedir l.text 
        end
      end
  end
  
  def speech(l)
    @out.start_speech
    l.elements.each do |s|
        case s.name
          when 'SPEAKER'
            @out.speaker s.text 
          when 'LINE'
            @out.start_line
            lines(s) 
          when 'STAGEDIR','SUBHEAD'
            @out.speech_stagedir s.text 
        end
    end
  end

  def lines(l) 
    l.children.each do |c|
      case c.node_type
      when :text
        @out.text c.to_s.strip 
      when :element
        @out.parenthetical c.text.strip
      end
    end
  end
end

class Collector
  def method_missing(method,*args)
    puts "#{method} -> #{args.inspect}"
  end
end

class InMemoryHashCollector < Collector
  def initialize()
    @play = {}
  end

  def play
    @play
  end

  def play_title title
    @play[:title] = title
  end
  
  def play_subtitle subtitle
    @play[:subtitle] = subtitle
  end

  def start_act 
    @play[:acts] ||= []
    @current_act = {}
    @play[:acts] << @current_act
  end

  def start_prologue
    start_act
    start_scene
  end

  def start_induct
    start_act
    start_scene
  end

  def start_epilogue
    start_act
    start_scene
  end

  def start_act_epilogue
    start_scene
  end

  def start_act_prologue
    start_scene
  end

  def act_title title
    @current_act[:title] = title
  end

  def start_scene
    @current_act[:scenes] ||= []
    @current_scene = {:parts => []}
    @current_act[:scenes] << @current_scene
  end

  def scene_title title
    @current_scene[:title] = title
  end

  def start_speech
    @current_speech = { speakers: [], lines: [] }
    @current_scene[:parts] << @current_speech
  end

  def speaker speaker
    @current_speech[:speakers] << speaker
  end

  def start_line 
    @current_line_parts = {:type => :lines, :lines => [] }
    @current_speech[:lines] << @current_line_parts
  end

  def scene_stagedir stagedir
    stagedir = {:stagedir => stagedir}
    @current_scene[:parts] << stagedir
  end

  def speech_stagedir stagedir
    @current_speech[:lines] << {:type => :stagedir, :text => stagedir } 
  end

  def text text
    lines = @current_line_parts[:lines]
    if lines.length > 0 and lines[-1][:type] == :line 
       lines[-1][:text] << text 
    else
       @current_line_parts[:lines] << {:type => :line, :text => text }
    end
  end

  def parenthetical text
    @current_line_parts[:lines] << {:type => :parenthetical, :text => text }
  end
end

def find_template(filename)
  Erubis::EscapedEruby.new(File.read(relative_path(filename)))
end

def parse_plays(glob)
  files_to_process = Dir.glob(glob)
  files_to_process.each do |f|
    doc = REXML::Document.new(File.new(f))
    c = InMemoryHashCollector.new
    p = PlayParser.new(c) 
    p.scan(doc)
    yield f, c.play
  end
end

def do_templating(template, template_vars, filename)
  html = template.result(template_vars)
  out = File.new(filename,"w")
  out.write html
  return out
end

play_template = find_template("etc/play.erb") 
index_template = find_template("etc/index.erb")

plays = []
parse_plays("#{SRC_FOLDER}/*.xml") do |file, play|
  filename = file.gsub("xml","html").gsub("#{SRC_FOLDER}/","#{DEST_FOLDER}/")
  out = do_templating(play_template, {"play"=>play}, filename)
  puts "#{File.basename(file)}\t->\t#{File.basename(out)}"
  plays << {:title => play[:title], :subtitle => play[:subtitle], :file => File.basename(out)}
end

do_templating(index_template, {"index"=>plays}, "#{DEST_FOLDER}/index.html")
