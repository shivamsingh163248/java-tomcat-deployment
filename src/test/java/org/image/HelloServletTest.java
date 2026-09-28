package org.image;

import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.junit.jupiter.api.Test;

import java.io.PrintWriter;
import java.io.StringWriter;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

class HelloServletTest {
    @Test
    void writesTheApplicationGreeting() throws Exception {
        HelloServlet servlet = new HelloServlet();
        HttpServletRequest request = mock(HttpServletRequest.class);
        HttpServletResponse response = mock(HttpServletResponse.class);
        StringWriter body = new StringWriter();
        when(response.getWriter()).thenReturn(new PrintWriter(body));

        servlet.doGet(request, response);

        assertEquals(
                "Hello and welcome!" + System.lineSeparator()
                        + "i = 1" + System.lineSeparator()
                        + "i = 2" + System.lineSeparator()
                        + "i = 3" + System.lineSeparator()
                        + "i = 4" + System.lineSeparator()
                        + "i = 5" + System.lineSeparator(),
                body.toString());
    }
}
