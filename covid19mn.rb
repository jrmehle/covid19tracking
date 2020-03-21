%w{ nokogiri json open-uri sqlite3 chronic gruff }.sort.each { |g| require g }

class Covid19mn
  DB_NAME = 'covid19mn.db'.freeze
  GRAPH_SIZE = '1200x550'

  def db
    db ||= SQLite3::Database.new "db/#{DB_NAME}"
  end

  def create_table
    db.execute <<-SQL
      create table patients (
        us_state text,
        patients_tested_positive integer,
        patients_tested_negative integer,
        patients_test_pending integer,
        patients_died integer,
        patients_total integer,
        record_date text
      );

      create unique index idx_patients_record_date on patients (record_date);
    SQL
  end

  def save_record(us_state: , patients_tested_positive: , patients_tested_negative: , patients_test_pending: , patients_died: , patients_total: , record_date: )
    sql = <<-SQL
      insert into patients values ( ?, ?, ?, ?, ?, ?, ? );
    SQL

    db.execute sql, us_state, patients_tested_positive, patients_tested_negative, patients_test_pending, patients_died, patients_total, record_date
  end

  def data
    sql = <<-SQL
      select * from patients order by record_date;
    SQL

    db.execute sql
  end

  def scrape_mn_health_dept_page
    page = Nokogiri::HTML(open('https://www.health.state.mn.us/diseases/coronavirus/situation.html'))

    as_of_date_p = page.css("p:contains(\"As of\")")
    as_of_date = Chronic.parse(as_of_date_p.text.gsub(/^As\ of\ /, '')).strftime('%F')

    patients_tested_li = page.css("li:contains(\"Approximate number of patients tested\")")
    patients_tested = patients_tested_li.text.scan(/\d/).join('').to_i

    patients_positive_li = page.css("li:contains(\"Positive:\")")
    patients_positive = patients_positive_li.text.scan(/\d/).join('').to_i

    patient_deaths_li = page.css("li:contains(\"Deaths:\")")
    patient_deaths = patient_deaths_li.text.scan(/\d/).join('').to_i

    patients_negative = patients_tested - patients_positive

    patients_pending = 0

    patients_recovered = 0

    { patients_total: patients_tested,
      patients_positive: patients_positive,
      patients_negative: patients_negative,
      patients_pending: patients_pending,
      patient_deaths: patient_deaths,
      patients_recovered: patients_recovered,
      as_of_date: as_of_date,
      us_state: 'MN' }
  end

  def retrieve_all_state_data
    json_data = JSON.parse(open('https://covidtracking.com/api/states').read)
  end

  def generate_graph(title: , data_title: , file_name: , graph_data: , labels_data: , colors: )
    g = Gruff::Line.new(GRAPH_SIZE)
    g.title = title
    g.theme = {
      colors: colors,
      marker_color: '#222222',
      font_color: '#222222',
      background_colors: %w(white #BBBBBB)
    }
    g.labels = labels_data
    g.data(data_title, graph_data)
    g.write(file_name)
  end

  def generate_graphs
    puts 'Generating graphs...'

    dates = data.map { |record| Chronic.parse(record[6]).strftime('%-m-%-d') }

    generate_graph(title: 'COVID-19 Minnesota',
                   data_title: 'Positive Cases',
                   file_name: 'images/covid19mn-positive_cases.png',
                   graph_data: data.map { |record| record[1] },
                   labels_data: Hash[(0...dates.size).zip dates],
                   colors: %w(red black))

    generate_graph(title: 'COVID-19 Minnesota',
                   data_title: 'Tests Conducted',
                   file_name: 'images/covid19mn-tests_conducted.png',
                   graph_data: data.map { |record| record[5] ? record[5] : 0 },
                   labels_data: Hash[(0...dates.size).zip dates],
                   colors: %w(#4B3EC4 black))

    generate_graph(title: 'COVID-19 Minnesota',
                   data_title: 'Deaths',
                   file_name: 'images/covid19mn-deaths.png',
                   graph_data: data.map { |record| record[4] ? record[4] : 0 },
                   labels_data: Hash[(0...dates.size).zip dates],
                   colors: %w(#222222))

    puts 'Done!'
  end

  def do_mn
    results = scrape_mn_health_dept_page

    puts "Tested: #{results[:patients_total]}"
    puts "Positive: #{results[:patients_positive]}"
    puts "Negative: #{results[:patients_negative]}"
    puts "Deaths: #{results[:patient_deaths]}"
    puts "Total: #{results[:patients_total]}"
    puts "As of #{results[:as_of_date]}"

    begin
      save_record(us_state: results[:us_state],
                  patients_tested_positive: results[:patients_positive],
                  patients_tested_negative: results[:patients_negative],
                  patients_test_pending: results[:patients_pending].zero? ? nil : results[:patients_pending],
                  patients_died: results[:patient_deaths],
                  patients_total: results[:patients_total],
                  record_date: results[:as_of_date])
    rescue StandardError => e
      puts "Record already created for: #{results[:as_of_date]}"
    end

    generate_graphs
  end

  def execute_all_states
    results = retrieve_all_state_data

    results.each do |state_data|
      parsed_date = Chronic.parse(state_data['lastUpdateEt']).strftime('%F')
      puts parsed_date
      puts "us_state: #{state_data['state']}"
      puts "patients_tested_positive: #{state_data['positive']}"
      puts "patients_tested_negative: #{state_data['negative']}"
      puts "patients_test_pending: #{state_data['pending']}"
      puts "patients_died: #{state_data['death']}"
      puts "patients_total: #{state_data['total']}"
      puts "record_date: #{parsed_date}"
      puts '-' * 80

      begin
        save_record(us_state: state_data['state'],
                    patients_tested_positive: state_data['positive'],
                    patients_tested_negative: state_data['negative'],
                    patients_test_pending: state_data['pending'],
                    patients_died: state_data['death'],
                    patients_total: state_data['total'],
                    record_date: parsed_date)
      rescue StandardError => e
        puts "Record already created for: #{parsed_date}"
      end
    end
  end

  def execute(mode = 'mn_only')
    create_table unless File.exist?("db/#{DB_NAME}")

    if mode == 'mn_only'
      do_mn
    else
      execute_all_states
    end
  end
end

Covid19mn.new.execute
