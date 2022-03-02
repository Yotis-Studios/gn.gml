__gnInit();

// test code
gn_setConnectHandler(testOnConnect);
gn_setDataHandler(testOnData);
conn = gn_connect("127.0.0.1", 8080);