require './bluecat_api.rb'


# For Bluecat POC work, we are looking for the following info:

# 1.	How to determine and connect to BlueCat system (ip, creds, anything else?) 
# 2.	Once we connect to BlueCat, how to request IPs out of the Bluecat system?  What info we need to provide?
# 3.	The API to allow ASM sends hostname and IP back to Bluecat and have it register them with DNS.  Again, what will be in input and output response.
# 4.	The API to allow ASM to return the set of IPs once we finish using them

# Run the poc to demonstrate above operations
bam = Bluecat::Api.new
bam.poc
