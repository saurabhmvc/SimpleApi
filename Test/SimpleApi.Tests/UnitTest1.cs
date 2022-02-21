using System;
using Xunit;
using SimpleApi;

namespace SimpleApi.Tests
{
    public class UnitTest1
    {
        ValuesController objValuesController = new ValuesController();

        [Fact]
        public void Test1()
        {
            var temp = objValuesController.Get(1);
            Assert.Equal("Saurabh Agarwal", temp);
        }
    }
}
