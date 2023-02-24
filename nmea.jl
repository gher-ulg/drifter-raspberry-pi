using Dates

function parse_nmea(line)
    if line == ""
        return nothing
    end
    @show line
    if occursin('*',line)
        line_,checksum = split(line,'*',limit=2)
        
        calculated_checksum =  reduce(xor,UInt8.(collect(line_[2:end])))

        if string(calculated_checksum,base=16,pad=2) != lowercase(checksum)
            @warn "checksum do not match" line checksum calculated_checksum
            return nothing
        end
    end
    
    parts = split(line_,',')

    if length(parts) == 0
        return nothing
    end
    
    if parts[1] == "\$GPGLL"
        if length(parts) != 8
            return nothing
        end

        lat = tryparse(Float64,parts[2])
        isnorth = parts[3] == "N"
        lon = tryparse(Float64,parts[4])
        iseast = parts[5] == "E"
        time_utc = Time(parts[6],"HHMMSS.ss")
        status = parts[7]
        valid = parts[8]                   

        if !isnothing(lon)
            lon /= 100
            if !isnorth
                lon = -lon
            end
        end

        if !isnothing(lat)
            lat /= 100

            if  !iseast
                lat = -lat
            end
        end

        return (; lon, lat, time_utc, status, valid)
    end
    return nothing
end

devicename = "/dev/ttyACM0"


last_saved = DateTime(1,1,1)

#=
for line in eachline(f)
    @show line
    while true
        pos = parse_nmea(line)
        while pos
        end
    end
end
=#

struct NMEADevice
    devicename::String
    iter
    state
end

function NMEADevice(devicename::String)
    dev = open(devicename,"r")     
    dev_lines = eachline(dev)        
    state = nothing
    NMEADevice(devicename,dev_lines,state)
end

function position(dev::NMEADevice)
    line,state = iterate(dev.iter,dev.state)
    return parse_nmea(line)
end

dev = NMEADevice(devicename)



#=
    next = iterate(dev_lines)

while next !== nothing
    (item, state) = next
    @show item
    # body
    next = iterate(dev_lines, state)
end
￼

line,state = iterate(dev_lines)

state,line = iterate(dev_lines)
  
=#

line = "\$GPGLL,5033.11111,N,00534.11111,E,161708.00,A,A*67"

hostname = gethostname()


fname = expanduser("~/track-gps-$hostname-$(Dates.format(Dates.now(),"yyyymmddTHHMMSS")).txt")

f = open(fname,"w")

while true
    pos = position(dev)
    time = Dates.now()

    if !isnothing(pos)
        @show pos
        longitude = pos.lon
        latitude = pos.lat
        
        println(f,time,",",longitude,",",latitude)
        flush(f)

        sleep(60)
    end    
end

close(f)
