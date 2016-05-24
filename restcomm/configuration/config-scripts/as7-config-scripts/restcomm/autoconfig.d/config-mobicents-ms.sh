#!/bin/bash
## Description: Configures the Media Server
## Author: Henrique Rosa (henrique.rosa@telestax.com)

configServerBeans() {
	FILE=$MMS_HOME/deploy/server-beans.xml
	MSERVER_EXTERNAL_ADDRESS="$MEDIASERVER_EXTERNAL_ADDRESS"

	if [ "$MSERVER_EXTERNAL_ADDRESS" = "$1" ]; then
   		MSERVER_EXTERNAL_ADDRESS="\<null\/\>"
	fi

	sed -e "s|<property name=\"bindAddress\">.*<\/property>|<property name=\"bindAddress\">$1<\/property>|" \
	    -e "s|<property name=\"localBindAddress\">.*<\/property>|<property name=\"localBindAddress\">$1<\/property>|" \
		-e "s|<property name=\"externalAddress\">.*</property>|<property name=\"externalAddress\">$MSERVER_EXTERNAL_ADDRESS</property>|" \
	    -e "s|<property name=\"localNetwork\">.*<\/property>|<property name=\"localNetwork\">$2<\/property>|" \
	    -e "s|<property name=\"localSubnet\">.*<\/property>|<property name=\"localSubnet\">$3<\/property>|" \
	    -e 's|<property name="useSbc">.*</property>|<property name="useSbc">true</property>|' \
	    -e 's|<property name="dtmfDetectorDbi">.*</property>|<property name="dtmfDetectorDbi">0</property>|' \
	    -e "s|<property name=\"lowestPort\">.*</property>|<property name=\"lowestPort\">$MEDIASERVER_LOWEST_PORT</property>|" \
	    -e "s|<property name=\"highestPort\">.*</property>|<property name=\"highestPort\">$MEDIASERVER_HIGHEST_PORT</property>|" \
	    $FILE > $FILE.bak
	mv $FILE.bak $FILE
	echo 'Configured UDP Manager'
}

configJavaOptsMem() {
    FILE=$MMS_HOME/bin/run.sh

	# Find total available memory on the instance
    TOTAL_MEM=$(free -m -t | grep 'Total:' | awk '{print $2}')
    # get 20 percent of available memory
    # need to use division by 1 for scale to be read
    CHUNK_MEM=$(echo "scale=0; ($TOTAL_MEM * 0.2)/1" | bc -l)
    # divide chunk memory into units of 64mb
    MULTIPLIER=$(echo "scale=0; $CHUNK_MEM/64" | bc -l)
    # use multiples of 64mb to know effective memory
    FINAL_MEM=$(echo "$MULTIPLIER * 64" | bc -l)
    MEM_UNIT='m'

    MMS_OPTS="-Xms$FINAL_MEM$MEM_UNIT -Xmx$FINAL_MEM$MEM_UNIT -XX:MaxPermSize=256m -Dorg.jboss.resolver.warning=true -Dsun.rmi.dgc.client.gcInterval=3600000 -Dsun.rmi.dgc.server.gcInterval=3600000"

	sed -e "/# Setup MMS specific properties/ {
		N; s|JAVA_OPTS=.*|JAVA_OPTS=\"$MMS_OPTS\"|
	}" $FILE > $FILE.bak
	mv $FILE.bak $FILE
	echo "Updated Java Options for Media Server: $MMS_OPTS"
}

configLogDirectory() {
	FILE=$MMS_HOME/conf/log4j.xml
	DIRECTORY=$MMS_HOME/log

	sed -e "/<param name=\"File\" value=\".*server.log\" \/>/ s|value=\".*server.log\"|value=\"$DIRECTORY/server.log\"|" \
	    $FILE > $FILE.bak
	mv $FILE.bak $FILE
	echo 'Updated log configuration'
}

## Description: Configures Media Server Manager
## Parameters :
## 		1.BIND_ADDRESS
## 		2.MEDIASERVER_EXTERNAL_ADDRESS

configMediaServerManager() {
	FILE=$RESTCOMM_DEPLOY/WEB-INF/conf/restcomm.xml
	bind_address="$1"
	ms_address="$2"
	ms_external_address="$3"
		sed -e "s|<local-address>.*</local-address>|<local-address>$bind_address</local-address>|" \
			-e "s|<local-port>.*</local-port>|<local-port>$LOCALMGCP</local-port>|" \
			-e "s|<remote-address>.*</remote-address>|<remote-address>$ms_address</remote-address>|" \
			-e "s|<remote-port>.*</remote-port>|<remote-port>$REMOTEMGCP</remote-port>|" \
			-e "s|<response-timeout>.*</response-timeout>|<response-timeout>500</response-timeout>|" \
			-e "s|<\!--.*<external-address>.*</external-address>.*-->|<external-address>$ms_external_address</external-address>|" \
			-e "s|<external-address>.*</external-address>|<external-address>$ms_external_address</external-address>|" $FILE > $FILE.bak

		mv $FILE.bak $FILE
		echo 'Configured Media Server Manager'
}

## MAIN
if [[ -z "$MEDIASERVER_LOWEST_PORT" ]]; then
	MEDIASERVER_LOWEST_PORT="34534"
fi
if [[ -z "$MEDIASERVER_HIGHEST_PORT" ]]; then
	MEDIASERVER_HIGHEST_PORT="65535"
fi

if [[ "$TRUSTSTORE_FILE" == '' ]]; then
	echo "TRUSTSTORE_FILE is not set";
	FILE=$MMS_HOME/bin/run.sh
	sed -e "/# Setup MMS specific properties/ {
		N; s|JAVA_OPTS=.*|JAVA_OPTS=\"-Dprogram\.name=\\\$PROGNAME \\\$JAVA_OPTS\"|
	}" $FILE > $FILE.bak
	mv $FILE.bak $FILE
else
	echo "TRUSTSTORE_FILE is set to '$TRUSTSTORE_FILE'";
	if [[ "$TRUSTSTORE_PASSWORD"  == '' ]]; then
		echo "TRUSTSTORE_PASSWORD is not set";
	else
		echo "TRUSTSTORE_PASSWORD is set to '$TRUSTSTORE_PASSWORD' will properly configure MMS";
		FILE=$MMS_HOME/bin/run.sh
		if [[ "$TRUSTSTORE_FILE" = /* ]]; then
			CERTIFICATION_FILE=$TRUSTSTORE_FILE
		else
			CERTIFICATION_FILE=$RESTCOMM_HOME/standalone/configuration/$TRUSTSTORE_FILE
		fi
		JAVA_OPTS_TRUSTORE="-Djavax.net.ssl.trustStore=$CERTIFICATION_FILE -Djavax.net.ssl.trustStorePassword=$TRUSTSTORE_PASSWORD"
		sed -e "/# Setup MMS specific properties/ {
		  N; s|JAVA_OPTS=.*|JAVA_OPTS=\"-Dprogram\.name=\\\$PROGNAME \\\$JAVA_OPTS $JAVA_OPTS_TRUSTORE\"|
		}" $FILE > $FILE.bak
		mv $FILE.bak $FILE
		echo "Properly configured MMS to use trustStore file $RESTCOMM_HOME/standalone/configuration/$TRUSTSTORE_FILE"
	fi
fi

echo "Configuring Mobicents Media Server... MS_ADDRESS $MS_ADDRESS BIND_ADDRESS $BIND_ADDRESS NETWORK $NETWORK SUBNET_MASK $SUBNET_MASK RTP_LOW_PORT $MEDIASERVER_LOWEST_PORT RTP_HIGH_PORT $MEDIASERVER_HIGHEST_PORT"
if [ -z "$MS_ADDRESS" ]; then
		MS_ADDRESS=$BIND_ADDRESS
fi

if [ -z "$MS_NETWORK" ]; then
      MS_NETWORK=$NETWORK
fi

if [ -z "$MS_SUBNET_MASK" ]; then
      MS_SUBNET_MASK=$SUBNET_MASK
fi
#Check for Por Offset
if (( $PORT_OFFSET > 0 )); then
	LOCALMGCP=$((LOCALMGCP + PORT_OFFSET))
	REMOTEMGCP=$((REMOTEMGCP + PORT_OFFSET))
fi

configServerBeans "$MS_ADDRESS" "$MS_NETWORK" "$MS_SUBNET_MASK"
#configJavaOpts
configLogDirectory
configMediaServerManager "$BIND_ADDRESS" "$MS_ADDRESS" "$MEDIASERVER_EXTERNAL_ADDRESS"
echo 'Finished configuring Mobicents Media Server!'
