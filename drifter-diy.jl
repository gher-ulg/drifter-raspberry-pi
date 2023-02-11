using Dates
using TOML
using LibSerialPort
using GSMHat
import GSMHat: start_modem, waitfor, enable_gnss, get_gnss, send_message, cmd, unlook

using Logging
debug_logger = ConsoleLogger(stderr, Logging.Debug);
global_logger(debug_logger)


@info "starting $(Dates.now())"

confname = joinpath(dirname(@__FILE__),"drifter-diy.toml")
config =
    open(confname) do f
        TOML.parse(f)
    end

phone_number = config["phone_number"]
local_SMS_service_center = config["local_SMS_service_center"]
pin = config["pin"]
APN = config["access_point_network"]
portname = config["portname"]
baudrate = config["baudrate"]

sleep(60)
@info "phone number $phone_number"


sp = GSMHat.init(portname, baudrate; pin=pin)


# power GNSS  on
@info "enable GNSS"
enable_gnss(sp)

# query if GNSS is powerd on
@info "query GNSS"
response = cmd(sp, "AT+CGNSPWR?")

hostname = gethostname()

while true
    # https://web.archive.org/web/20230121160033/https://docs.eseye.com/Content/ELS61/ATCommands/ELS61CREG.htm
    reg_status = cmd(sp,"AT+CREG?")
    modus,status = split(split(reg_status[1],':')[2],',')
    @info "registration status" reg_status
    if status in ("1","5")
        break
    else
        @info "registration status" reg_status
        sleep(20)
    end
end


@info "send first message"
message = "$hostname ready, switching GNSS on"

ntry_message_send = 10

for i = 1:ntry_message_send
    try
        send_message(sp,phone_number,local_SMS_service_center,message)
        break
    catch err
        @info "catched error (try $i) " err

        reg_status = cmd(sp,"AT+CREG?")
        @info "registration status" reg_status

        if i == ntry_message_send
            @info("sending message failed after $ntry_message_send")
            rethrow()
        else
            sleep(60)
        end
    end
end

last_message = DateTime(1,1,1)
last_save = DateTime(1,1,1)
fname = expanduser("~/track-$hostname-$(Dates.format(Dates.now(),"yyyymmddTHHMMSS")).txt")
isfile(fname) && rm(fname)
dt_message = Dates.Second(config["message_every_seconds"])
dt_save = Dates.Second(config["save_every_seconds"])

@info "saving location every $dt_save in $fname"
@info "sending location every $dt_message to $phone_number"

gnss_fix = false
gnss_retry = 0
time = longitude = latitude = nothing
open(fname,"a+") do f
    while true
        global last_message, last_save, gnss_retry, gnss_fix
        global time, longitude, latitude

        now = Dates.now()

        # GNSS coordinates
        while true
            time,longitude,latitude = get_gnss(sp)

            if !isnothing(time) && !isnothing(latitude) && !isnothing(longitude)
                gnss_fix = true
                gnss_retry = 0
                break
            else
                gnss_retry = gnss_retry+1
            end

            if gnss_fix && (gnss_retry > 60)
                GSMHat.reset(sp)
                GSMHat.unlook(sp,pin)
                # echo state remains off
                gnss_retry = 0
            end
            sleep(10)
        end


        if now - last_message >  dt_message
            message = "sigo vivo, estoy en $longitude, $latitude, $time"
            @info "sending: $message"
            send_message(sp,phone_number,local_SMS_service_center,message)
            last_message = now
        end

        if now - last_save >  dt_save
            println(f,time,",",longitude,",",latitude)
            flush(f)
            last_save = now
        end

        messages = GSMHat.get_messages(sp)
        @info "$(length(messages)) message(s)"
        for message in messages
            if strip(lowercase(message.sms_message_body)) == "status"
                msg = "sigo vivo, estoy en $longitude, $latitude, $time"
                @info "send status $msg"
                send_message(sp,phone_number,local_SMS_service_center,msg)

                GSMHat.delete_message(sp, message.index)
            end
        end
        #sleep(5)
        sleep(min(dt_save,dt_message))
    end
end

close(sp)
