# HTMLをテキストに変換するメソッド
def html_to_text(html_data)
    begin
      # HTMLをテキストに変換する処理を実装
      # ここでは簡単な実装例を示します
      # 実際のアプリケーションではgemやライブラリを使用することが推奨されます
      # この例ではNokogiriを使用してHTMLを解析してテキストに変換するとします
      require 'nokogiri'
      doc = Nokogiri::HTML.parse(html_data)
      # テキストに変換した結果を返す
      doc.text
    rescue StandardError => e
      # エラーメッセージを出力して空の文字列を返す
      puts "HTMLのテキスト変換中にエラーが発生しました: #{e.message}"
      ''
    end
  end
  
  begin
    # 標準入力からデータを読み込む
    input_data = $stdin.read
  
    # デバッグ用に入力データを表示
  
    # 読み込んだデータがHTML形式かどうかを判定する
   if input_data.strip.downcase.include?('<br>') || input_data.strip.downcase.include?('<!doctype html>') || input_data.strip.downcase.include?('<html') || input_data.strip.downcase.include?('<div>')
     # HTML形式の場合はテキストに変換する
     text_data = html_to_text(input_data)
     # テキストデータを標準出力に出力する
     puts text_data
   else
     # HTML形式でない場合はそのまま出力する
     puts input_data
    end
  rescue StandardError => e
    # エラーメッセージを出力
    puts "エラーが発生しました: #{e.message}"
  end
  