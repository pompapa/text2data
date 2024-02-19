require 'csv'
require 'yaml'
require 'rubyXL'
require 'rubyXL/convenience_methods'
require 'open3'
require 'optparse'

# ファイル操作とデータ変換を行うスクリプト。
# CSV、Excel、AsciiDoc形式への変換をサポートし、外部スクリプトによるデータ加工も可能。
# ファイルの読み込み、データの解析、変換、および出力を行います。

class FileHandler
  # ファイルを読み込み、その内容を行ごとに配列として返します。
  # @param filename [String] 読み込むファイルの名前
  # @return [Array<String>] ファイルの各行の内容
  # @raise [RuntimeError] ファイルが存在しないか読み取り不可能な場合
  def self.read_file(filename)
      unless File.exist?(filename)
        raise "ファイルが存在しません: #{filename}"
      end
      unless File.readable?(filename)
        raise "ファイルが読み取り不可能です: #{filename}"
      end
      File.open(filename, "r") { |file| file.readlines.map(&:strip) }
    rescue IOError => e
      raise "ファイルの読み込み中にエラーが発生しました（#{filename}）: #{e.message}"
    end
  # 与えられたデータをCSVファイルとして書き込みます。
  # @param filename [String] 出力先のCSVファイル名
  # @param data [Array<Array<String>>] CSVに書き込むデータ
  # @raise [RuntimeError] ファイルの書き込みに失敗した場合
  
    def self.write_csv(filename, data)
      CSV.open(filename, "w", force_quotes: true) do |csv|
        data.each { |row| csv << row }
      end
    rescue IOError => e
      raise "CSVファイルの書き込み中にエラーが発生しました（#{filename}）: #{e.message}"
    end
  # ワークブックオブジェクトをExcelファイルとして書き込みます。
  # @param filename [String] 出力先のExcelファイル名
  # @param workbook [RubyXL::Workbook] 書き込むExcelのワークブックオブジェクト
  # @raise [RuntimeError] ファイルの書き込みに失敗した場合
  
    def self.write_excel(filename, workbook)
      workbook.write(filename)
    rescue IOError => e
      raise "Excelファイルの書き込み中にエラーが発生しました（#{filename}）: #{e.message}"
    end
  end

# 外部スクリプトの実行機能を専門に扱うモジュール
module ExternalScriptRunner
  # 指定された外部スクリプトを実行し、結果を返します。
  # @param data [String] スクリプトに渡す入力データ
  # @param script_path [String] 実行する外部スクリプトのパス
  # @return [String] スクリプトの実行結果
  # @raise [RuntimeError] スクリプト実行に失敗した場合
  def self.run_script(data, script_path)
    stdout_str, stderr_str, status = Open3.capture3("ruby #{script_path}", stdin_data: data)
    unless status.success?
      raise "外部スクリプトの実行に失敗しました（#{script_path}）: #{stderr_str}"
    end
    stdout_str.chomp
  rescue => e
    raise "外部スクリプトの実行中に例外が発生しました（#{script_path}）: #{e.message}"
  end

end

class TextToDataConverter
  # コンストラクタ。初期化に必要な情報を引数として受け取ります。
  # @param input_filename [String] 入力テキストファイルの名前
  # @param output_filename [String] 出力ファイルの名前
  # @param pattern_files [Array<String>] パターン設定ファイル（YAML形式）のリスト
  # @param format [String] 出力フォーマット（'csv'、'excel'、または 'adoc'）
  def initialize(input_filename, output_filename, pattern_files, format,no_external_script)
    @input_filename = input_filename
    @output_filename = output_filename
    @patterns = merge_patterns(pattern_files)
    @no_external_script = no_external_script
    @data = []
    @current_row = {}
    @previous_line = ''
    @first_column_id = @patterns['columns'].first['id']
    @format = format
    @header_style = format_header_style
    @cell_styles = format_cell_styles
  end

  # メインの変換プロセスを実行するメソッド。
  def convert
    read_and_process_file
    write_output
  end

  private

  # 複数のパターンファイルをマージし、1つのパターン辞書を作成するメソッド。
  # @param pattern_files [Array<String>] パターン設定ファイル（YAML形式）のリスト
  # @return [Hash] マージされたパターン設定
  def merge_patterns(pattern_files)
    patterns = {}
    pattern_files.each do |pattern_file|
      raise "YAMLファイルが存在しないか読み取り不可能です: #{pattern_file}" unless File.exist?(pattern_file)
      file_patterns = YAML.load_file(pattern_file)
      patterns = deep_merge_patterns(patterns, file_patterns)
    end
    patterns
  end

  # 2つのパターン辞書を深くマージするメソッド。辞書のキーが重複している場合、新しい値で上書きされます。
  # @param existing_patterns [Hash] 既存のパターン設定
  # @param new_patterns [Hash] 新しいパターン設定
  # @return [Hash] マージされたパターン設定
  def deep_merge_patterns(existing_patterns, new_patterns)
    existing_patterns.merge(new_patterns) do |key, old_val, new_val|
      old_val.is_a?(Hash) && new_val.is_a?(Hash) ? deep_merge_patterns(old_val, new_val) : new_val
    end
  end

  # テキストファイルを読み込み、行ごとに処理するメソッド。
  # @raise [RuntimeError] ファイルの読み込みに失敗した場合
  def read_and_process_file
    lines = FileHandler.read_file(@input_filename)
    lines.each do |line|
      process_line(line)
    end
    @data << @current_row unless @current_row.empty?
  end

  # 各行を処理し、適切な列にデータを割り当てるメソッド。
  # @param line [String] 処理するテキスト行
  def process_line(line)
    matched_column = match_column(line)
    if matched_column
      if matched_column == @first_column_id && !@current_row.empty?
        @data << @current_row
        @current_row = {}
      end
      handle_new_column(matched_column, line)
    else
      append_to_current_column(line)
    end
    @previous_line = line
  end

  # 新しい列の処理を開始するメソッド。列の設定に基づいてデータを処理します。
  # @param column_id [String] 新しい列のID
  # @param line [String] 処理するテキスト行
  def handle_new_column(column_id, line)
    column_config = @patterns['columns'].find { |col| col['id'] == column_id }
    if column_config['position'] == 'previous'
      data = @previous_line
      @current_row[column_id] = { id: column_id, data: data, lines: column_config['lines'], xscript: column_config['xscript'] }
    elsif column_config['position'] == 'following'
      if column_config['lines'] == 'single'
        handle_single_line(column_id, column_config, line)
      else
        include_line = column_config['include_pattern_line'] ? line : ''
        @current_row[column_id] = { id: column_id, data: include_line, lines: 'multiple', xscript: column_config['xscript'] }
      end
    end
  end

  # 単一行の列データを処理するメソッド。列の設定に基づいてデータを割り当てます。
  # @param column_id [String] 処理する列のID
  # @param column_config [Hash] 列の設定
  # @param line [String] 処理するテキスト行
  def handle_single_line(column_id, column_config, line)
    if column_config['include_pattern_line']
      @current_row[column_id] = { id: column_id, data: line, lines: 'single', xscript: column_config['xscript'] }
    else
      @current_row[column_id] = { id: column_id, data: '', lines: 'single', include_next_line: true, xscript: column_config['xscript'] }
    end
  end

  # 現在の列にデータを追加するメソッド。複数行のデータを処理する際に使用します。
  # @param line [String] 追加するテキスト行
  def append_to_current_column(line)
    return if @current_row.empty?
    current_column_id = @current_row.keys.last
    column_config = @current_row[current_column_id]
    if column_config[:lines] == 'multiple' || column_config[:include_next_line]
      @current_row[current_column_id][:data] += (column_config[:data].empty? ? '' : "\n") + line
      @current_row[current_column_id].delete(:include_next_line)
    end
  end

  # テキスト行が特定の列に一致するかどうかを判定するメソッド。
  # @param line [String] 判定するテキスト行
  # @return [String, nil] 一致する列のID、または一致しない場合はnil
  def match_column(line)
    @patterns['columns'].each do |column|
      return column['id'] if line.match?(Regexp.new(column['pattern']))
    end
    nil
  end

  # ファイル形式に応じて適切な出力メソッドを呼び出すメソッド。
  # @raise [RuntimeError] 未知のフォーマットが指定された場合
  def write_output
    case @format
    when 'csv'
      write_csv
    when 'excel'
      write_excel
    when 'adoc'
      write_adoc
    else
      raise "未知のファイル形式: #{@format}"
    end
  end

  # CSV形式でデータを出力するメソッド。
  # 出力先が指定されていない場合、標準出力に出力します。
  def write_csv
    prepared_data = prepare_data_for_output
    if @output_filename
      FileHandler.write_csv(@output_filename, prepared_data)
    else
      prepared_data.each { |row| puts CSV.generate_line(row) }
    end
  end

  # AsciiDoc形式でデータを出力するメソッド。
  # 出力先が指定されていない場合、標準出力に出力します。
  def write_adoc
    csv_data = prepare_csv_data
    adoc_content = convert_csv_to_adoc(csv_data)
    if @output_filename
      File.write(@output_filename, adoc_content)
    else
      puts adoc_content
    end
  end

  # Excel形式でデータを出力するメソッド。
  # 出力ファイル名が指定されていない場合、例外を発生させます。
  def write_excel
    if @output_filename.nil?
      raise "Excelフォーマットでは出力ファイル名が必要です。"
    end
    workbook = RubyXL::Workbook.new
    worksheet = workbook[0]
    set_column_widths(worksheet)
    write_header_row(worksheet)
    prepared_data = prepare_data_for_output
    prepared_data.each_with_index do |row, row_index|
      row.each_with_index do |cell_data, column_index|
        cell = worksheet.add_cell(row_index + 1, column_index, cell_data)
        apply_cell_style(cell, @cell_styles[column_index])
      end
    end
    workbook.write(@output_filename)
  end

  # CSVデータを準備するメソッド。内部的にCSV形式に変換されたデータを返します。
  # @return [String] CSV形式に変換されたデータ
  def prepare_csv_data
    prepared_data = prepare_data_for_output
    prepared_data.map { |row| CSV.generate_line(row) }.join
  end

  # CSVデータをAsciiDoc形式に変換するメソッド。
  # @param csv_data [String] 変換するCSVデータ
  # @return [String] AsciiDoc形式に変換されたデータ
  def convert_csv_to_adoc(csv_data)
    adoc_content = "|===\n"
    @patterns['columns'].each do |column|
      adoc_content += "| #{column['header']} "
    end
    adoc_content += "\n"
    csv_data.each_line do |line|
      adoc_content += "| " + line.chomp.gsub(',', ' |') + "\n"
    end
    adoc_content += "|==="
    adoc_content
  end

  # Excelシートの列幅を設定するメソッド。
  # @param worksheet [RubyXL::Worksheet] 列幅を設定するExcelシート
  def set_column_widths(worksheet)
    @patterns['columns'].each_with_index do |column, index|
      column_width = column['width'] || 10
      worksheet.change_column_width(index, column_width)
    end
  end

  # ヘッダ行のスタイルを設定するメソッド。
  # @return [Hash] ヘッダ行のスタイル設定
  def format_header_style
    {
      font_name: @patterns['header']['font_name'],
      font_size: @patterns['header']['font_size'],
      fg_color: @patterns['header']['font_color'],
      bg_color: @patterns['header']['bg_color'],
      bold: @patterns['header']['bold'],
      horizontal_align: @patterns['header']['alignment'].to_sym,
      text_wrap: @patterns['text_wrap'] || @patterns['defaults']['text_wrap']
    }
  end

  # 各セルのスタイルを設定するメソッド。
  # @return [Array<Hash>] 各セルのスタイル設定のリスト
  def format_cell_styles
    @patterns['columns'].map do |column|
      {
        font_name: column['font_name'] || @patterns['defaults']['font_name'],
        font_size: column['font_size'] || @patterns['defaults']['font_size'],
        fg_color: column['font_color'] || @patterns['defaults']['font_color'],
        bg_color: column['bg_color'] || @patterns['defaults']['bg_color'],
        bold: column['bold'] || false,
        horizontal_align: (column['alignment'] || 'left').to_sym,
        text_wrap: column['text_wrap'] || @patterns['defaults']['text_wrap']
      }
    end
  end

  # ヘッダ行をExcelシートに書き込むメソッド。
  # @param worksheet [RubyXL::Worksheet] ヘッダ行を書き込むExcelシート
  def write_header_row(worksheet)
    @patterns['columns'].each_with_index do |column, index|
      cell = worksheet.add_cell(0, index, column['header'])
      apply_cell_style(cell, @header_style)
    end
  end

  # 個々のセルにスタイルを適用するメソッド。
  # @param cell [RubyXL::Cell] スタイルを適用するセル
  # @param style [Hash] 適用するスタイルの設定
  def apply_cell_style(cell, style)
    cell.change_font_name(style[:font_name])
    cell.change_font_size(style[:font_size])
    cell.change_font_color(style[:fg_color])
    cell.change_fill(style[:bg_color])
    cell.change_font_bold(style[:bold])
    cell.change_horizontal_alignment(style[:horizontal_align])
    cell.change_text_wrap(style[:text_wrap])
  end

  # 出力用のデータを準備するメソッド。列データを適切な形式に変換します。
  # @return [Array<Array<String>>] 変換されたデータ
  def prepare_data_for_output
    @data.map do |row|
      row_data = Array.new(@patterns['columns'].length)
      row.each do |column_id, column_data|
        index = @patterns['columns'].index { |col| col['id'] == column_id }
        row_data[index] = transform_column_data(column_data) if index
      end
      row_data
    end
  end

  # 列データを変換するメソッド。必要に応じて外部スクリプトを使用してデータを変換します。
  # @param col_data [Hash] 変換する列データ
  # @return [String] 変換されたデータ
  def transform_column_data(col_data)
    if col_data[:xscript] && !@no_external_script
      ExternalScriptRunner.run_script(col_data[:data], col_data[:xscript])
    else
      col_data[:data]
    end
  end
end

# ここにバージョン情報を追加
VERSION = '1.0.0'

# コマンドラインオプションの解析と実行のセットアップ
options = {}
OptionParser.new do |opts|
  opts.banner = "使用法: ruby script.rb [options] <input_file> <pattern_file1> [pattern_file2 ...]"

  opts.on("-f", "--format FORMAT", ["csv", "excel", "adoc"], "出力フォーマットを指定する (csv, excel, adoc)") do |format|
    options[:format] = format
  end

  opts.on("-o", "--output FILE", "出力ファイル名を指定する") do |file|
    options[:output] = file
  end

  opts.on("-nx", "YAMLによる外部プログラムの呼び出しを無視する") do
    options[:no_external_script] = true
  end

  # バージョン情報を表示するオプション
  opts.on_tail("-v", "--version", "バージョン情報を表示する") do
    puts "#{VERSION}"
    exit
  end

  opts.on_tail("-h", "--help", "ヘルプを表示する") do
    puts opts
    exit
  end
end.parse!

input_filename, *pattern_files = ARGV
format = options[:format] || 'csv'
output_filename = options[:output]
no_external_script = options[:no_external_script]

if input_filename.nil? || pattern_files.empty?
  puts "エラー: 入力ファイルおよび少なくとも1つのパターンファイルを指定してください。"
  exit
end

begin
  converter = TextToDataConverter.new(input_filename, output_filename, pattern_files, format,no_external_script)
  converter.convert
rescue StandardError => e
  puts "エラーが発生しました: #{e.message}"
end
