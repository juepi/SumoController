const port = 8080
const configFilePath = "./config.ini"

const fs = require('fs')
    , ini = require('ini')
    , bodyParser = require('body-parser')
    , express = require('express')


const app = express()
app.use(express.static('static'))
app.use(bodyParser.json())
app.use(bodyParser.urlencoded({ extended: true } ))

app.get('/', (request, response) => {
	response.send('Hi!!')
})

app.get('/getconfig', (request, response) => {
	var config = ini.parse(fs.readFileSync(configFilePath, 'utf-8'))
	response.send(config)
})

app.post('/setconfig', (request, response) => {
	fs.writeFileSync(configFilePath, ini.stringify(request.body))
})

app.listen(port, (err) => {
	if (err) {
		return console.log('Error: ', err)
	}

	console.log(`Listening on port ${port}`)
})
